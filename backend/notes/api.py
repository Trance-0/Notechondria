from datetime import datetime, timedelta, time

from django.db import transaction
from django.db.models import Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone

from rest_framework import permissions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from creators.utils import ensure_creator
from notechondria.utils import generate_unique_id

from .mark_down_parser import clean_block_string
from .models import (
    CalendarFeed,
    Course,
    CourseMedia,
    HeatmapActivityTypeChoices,
    Note,
    NoteActivitySession,
    NoteBlock,
    NoteVersion,
    NoteBlockTypeChoices,
    NoteIndex,
    PlannerEvent,
)
from .services import (
    block_word_count,
    build_heatmap_payload,
    calendar_week_payload,
    note_word_count,
    note_markdown,
    note_preview_lines,
    note_session_payload,
    planner_event_payload,
    record_note_activity,
    restore_note_version,
    snapshot_note_version,
    version_label,
)


def note_is_public(note: Note) -> bool:
    return bool(note.is_public or (note.course_id and note.course_id.is_default))


def can_access_note(request, note: Note) -> bool:
    if note_is_public(note):
        return True
    return bool(
        request.user
        and request.user.is_authenticated
        and note.creator_id.user_id_id == request.user.id
    )


def require_note_access(request, note_id: int) -> Note:
    note = get_object_or_404(Note.objects.select_related("course_id", "creator_id__user_id"), pk=note_id)
    if not can_access_note(request, note):
        raise serializers.ValidationError("You do not have access to this note.")
    return note


class CourseMediaSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = CourseMedia
        fields = ["id", "title", "description", "source", "image_url"]

    def get_image_url(self, obj):
        return obj.image.url if obj.image else ""


class NoteBlockSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = NoteBlock
        fields = [
            "id",
            "block_type",
            "text",
            "args",
            "is_AI_generated",
            "image_url",
            "date_created",
            "last_edit",
        ]

    def get_image_url(self, obj):
        return obj.image.url if obj.image else ""


class NoteSummarySerializer(serializers.ModelSerializer):
    excerpt = serializers.SerializerMethodField()
    editor_mode = serializers.CharField(read_only=True)
    preview_lines = serializers.SerializerMethodField()

    class Meta:
        model = Note
        fields = [
            "id",
            "title",
            "description",
            "excerpt",
            "preview_lines",
            "editor_mode",
            "is_public",
            "last_edit",
            "date_created",
            "course_id",
        ]

    def get_excerpt(self, obj):
        first_text_block = (
            NoteBlock.objects.filter(note_id=obj)
            .exclude(text__isnull=True)
            .exclude(text__exact="")
            .order_by("date_created")
            .first()
        )
        if first_text_block is None:
            return (obj.content or obj.description or "")[:220]
        return first_text_block.text[:220]

    def get_preview_lines(self, obj):
        return note_preview_lines(obj)


class NoteDetailSerializer(NoteSummarySerializer):
    blocks = serializers.SerializerMethodField()
    course = serializers.SerializerMethodField()
    content = serializers.CharField(read_only=True)
    metadata_json = serializers.CharField(read_only=True)

    class Meta(NoteSummarySerializer.Meta):
        fields = NoteSummarySerializer.Meta.fields + ["course", "blocks", "content", "metadata_json"]

    def get_blocks(self, obj):
        ordered_blocks = [
            handle.noteblock_id
            for handle in NoteIndex.objects.filter(note_id=obj).select_related("noteblock_id").order_by("index")
        ]
        return NoteBlockSerializer(ordered_blocks, many=True).data

    def get_course(self, obj):
        if obj.course_id is None:
            return None
        return {"id": obj.course_id.id, "title": obj.course_id.title, "slug": obj.course_id.slug}


class CourseSerializer(serializers.ModelSerializer):
    cover_image_url = serializers.SerializerMethodField()
    recent_notes = serializers.SerializerMethodField()
    media = CourseMediaSerializer(source="media_items", many=True, read_only=True)

    class Meta:
        model = Course
        fields = [
            "id",
            "slug",
            "title",
            "description",
            "cover_image_url",
            "is_default",
            "recent_notes",
            "media",
        ]

    def get_cover_image_url(self, obj):
        return obj.cover_image.url if obj.cover_image else ""

    def get_recent_notes(self, obj):
        recent_notes = obj.notes.order_by("-last_edit")[:5]
        return NoteSummarySerializer(recent_notes, many=True).data


class NoteWriteSerializer(serializers.Serializer):
    course_id = serializers.IntegerField(required=False, allow_null=True)
    title = serializers.CharField(max_length=100)
    description = serializers.CharField(allow_blank=True, required=False, allow_null=True)
    markdown = serializers.CharField(allow_blank=True, required=False)
    content = serializers.CharField(allow_blank=True, required=False)
    metadata_json = serializers.CharField(allow_blank=True, required=False)
    is_public = serializers.BooleanField(required=False)
    blocks = serializers.ListField(child=serializers.DictField(), required=False)
    editor_mode = serializers.ChoiceField(choices=[("G", "gfm"), ("B", "blocks"), ("P", "plain_text")], required=False)


class NoteVersionSerializer(serializers.ModelSerializer):
    label = serializers.SerializerMethodField()

    class Meta:
        model = NoteVersion
        fields = ["id", "title", "description", "content", "metadata_json", "editor_mode", "reason", "label", "date_created"]

    def get_label(self, obj):
        return version_label(obj)


class BlockWriteSerializer(serializers.Serializer):
    block_type = serializers.ChoiceField(choices=NoteBlockTypeChoices.choices)
    text = serializers.CharField(allow_blank=True, required=False)
    args = serializers.CharField(allow_blank=True, required=False, allow_null=True)
    is_AI_generated = serializers.BooleanField(required=False, default=False)


class ReorderSerializer(serializers.Serializer):
    ordered_block_ids = serializers.ListField(child=serializers.IntegerField(), min_length=1)


class PlannerEventWriteSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=120)
    event_date = serializers.DateField()
    starts_at = serializers.DateTimeField(required=False, allow_null=True)
    ends_at = serializers.DateTimeField(required=False, allow_null=True)
    difficulty_weight = serializers.IntegerField(min_value=1, required=False, default=1)
    description = serializers.CharField(allow_blank=True, required=False, allow_null=True)
    course_id = serializers.IntegerField(required=False, allow_null=True)


class NoteSessionWriteSerializer(serializers.Serializer):
    note_id = serializers.IntegerField()
    title = serializers.CharField(max_length=120, required=False, allow_blank=True)
    summary = serializers.CharField(max_length=255, required=False, allow_blank=True)
    started_at = serializers.DateTimeField(required=False, allow_null=True)
    ended_at = serializers.DateTimeField(required=False, allow_null=True)


class CalendarFeedWriteSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=120)
    source_kind = serializers.ChoiceField(choices=[("I", "import"), ("S", "subscribe")], required=False, default="I")
    source_url = serializers.URLField(required=False, allow_blank=True)
    raw_ical = serializers.CharField(required=False, allow_blank=True)
    course_id = serializers.IntegerField(required=False, allow_null=True)
    is_enabled = serializers.BooleanField(required=False, default=True)


class CalendarFeedSerializer(serializers.ModelSerializer):
    class Meta:
        model = CalendarFeed
        fields = [
            "id",
            "title",
            "source_kind",
            "source_url",
            "is_enabled",
            "course_id",
            "last_sync",
            "date_created",
            "last_edit",
        ]


class FrontPageApiView(APIView):
    permission_classes = [permissions.AllowAny]

    @staticmethod
    def health(request):
        return JsonResponse({"status": "ok"})

    def get(self, request):
        default_course = Course.objects.filter(is_default=True).prefetch_related("media_items").first()
        if default_course is None:
            default_course = Course.objects.order_by("title").first()
        recommended_notes = Note.objects.filter(is_public=True).order_by("-last_edit")[:12]
        payload = {
            "default_course": CourseSerializer(default_course).data if default_course else None,
            "recent_notes": NoteSummarySerializer(
                recommended_notes[:6],
                many=True,
            ).data,
            "recommended_notes": NoteSummarySerializer(recommended_notes, many=True).data,
            "collections": CourseSerializer(
                Course.objects.prefetch_related("media_items").order_by("-is_default", "title")[:6],
                many=True,
            ).data,
        }
        if request.user.is_authenticated:
            payload["heatmap"] = build_heatmap_payload(ensure_creator(request.user))
            payload["upcoming_events"] = [
                planner_event_payload(event)
                for event in PlannerEvent.objects.filter(
                    creator_id=ensure_creator(request.user),
                    event_date__gte=timezone.localdate(),
                ).order_by("event_date", "title")[:8]
            ]
        return Response(payload)


class CourseListApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        courses = Course.objects.prefetch_related("media_items").order_by("-is_default", "title")
        return Response(CourseSerializer(courses, many=True).data)


class CourseDetailApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, course_id):
        course = get_object_or_404(Course.objects.prefetch_related("media_items"), pk=course_id)
        return Response(CourseSerializer(course).data)


class CourseNotesApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, course_id):
        course = get_object_or_404(Course, pk=course_id)
        notes = course.notes.order_by("-last_edit")
        if not request.user.is_authenticated:
            notes = notes.filter(Q(is_public=True) | Q(course_id__is_default=True))
        return Response(NoteSummarySerializer(notes, many=True).data)


class NoteListCreateApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        course_id = request.query_params.get("course_id")
        query = request.query_params.get("q", "").strip()
        limit = request.query_params.get("limit")
        offset = int(request.query_params.get("offset", "0") or 0)
        notes = Note.objects.all()
        if course_id:
            notes = notes.filter(course_id_id=course_id)
        if query:
            notes = notes.filter(Q(title__icontains=query) | Q(content__icontains=query) | Q(description__icontains=query))
        if request.user.is_authenticated:
            notes = notes.filter(creator_id__user_id=request.user)
        else:
            notes = notes.filter(Q(is_public=True) | Q(course_id__is_default=True))
        notes = notes.order_by("-last_edit")
        if limit is not None:
            page_size = max(1, min(int(limit), 100))
            total = notes.count()
            rows = notes[offset: offset + page_size]
            return Response(
                {
                    "results": NoteSummarySerializer(rows, many=True).data,
                    "total": total,
                    "offset": offset,
                    "limit": page_size,
                    "has_more": offset + page_size < total,
                }
            )
        return Response(NoteSummarySerializer(notes, many=True).data)

    def post(self, request):
        if not request.user.is_authenticated:
            return Response({"detail": "Authentication required."}, status=status.HTTP_401_UNAUTHORIZED)
        serializer = NoteWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        creator = ensure_creator(request.user)
        course = None
        if serializer.validated_data.get("course_id"):
            course = get_object_or_404(Course, pk=serializer.validated_data["course_id"])
        elif Course.objects.filter(is_default=True).exists():
            course = Course.objects.filter(is_default=True).first()
        note = Note.objects.create(
            creator_id=creator,
            course_id=course,
            sharing_id=generate_unique_id(Note, "sharing_id"),
            title=serializer.validated_data["title"],
            description=serializer.validated_data.get("description") or "",
            is_public=serializer.validated_data.get("is_public", False),
            content=serializer.validated_data.get("content") or serializer.validated_data.get("markdown") or "",
            metadata_json=serializer.validated_data.get("metadata_json") or "",
            editor_mode=serializer.validated_data.get("editor_mode") or creator.editor_mode,
        )
        block_rows = serializer.validated_data.get("blocks")
        if block_rows:
            replace_note_blocks_from_payload(note, creator, block_rows)
        else:
            create_blocks_from_markdown(
                note=note,
                creator=creator,
                markdown=note.content or note.description or note.title,
            )
        record_note_activity(note, note_word_count(note), HeatmapActivityTypeChoices.CREATED)
        return Response(NoteDetailSerializer(note).data, status=status.HTTP_201_CREATED)


class NoteDetailApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, note_id):
        note = require_note_access(request, note_id)
        return Response(NoteDetailSerializer(note).data)

    def patch(self, request, note_id):
        if not request.user.is_authenticated:
            return Response({"detail": "Authentication required."}, status=status.HTTP_401_UNAUTHORIZED)
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can update this note."}, status=status.HTTP_403_FORBIDDEN)
        serializer = NoteWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field in ["title", "description", "metadata_json", "editor_mode", "is_public"]:
            if field in serializer.validated_data:
                setattr(note, field, serializer.validated_data[field])
        if "course_id" in serializer.validated_data:
            course_id = serializer.validated_data["course_id"]
            note.course_id = get_object_or_404(Course, pk=course_id) if course_id else None
        if "content" in serializer.validated_data:
            note.content = serializer.validated_data["content"]
        note.save()
        if "blocks" in serializer.validated_data:
            replace_note_blocks_from_payload(note, note.creator_id, serializer.validated_data["blocks"])
            note.content = markdown_from_blocks(serializer.validated_data["blocks"], fallback_title=note.title)
            note.save(update_fields=["content", "last_edit"])
            record_note_activity(note, note_word_count(note), HeatmapActivityTypeChoices.EDITED)
        elif "markdown" in serializer.validated_data or "content" in serializer.validated_data:
            before_words = note_word_count(note)
            replacement_markdown = serializer.validated_data.get("content") or serializer.validated_data.get("markdown") or note.content
            note.content = replacement_markdown
            note.save(update_fields=["content", "last_edit"])
            replace_note_blocks(note, note.creator_id, replacement_markdown)
            after_words = note_word_count(note)
            record_note_activity(
                note,
                max(abs(after_words - before_words), after_words),
                HeatmapActivityTypeChoices.EDITED,
            )
        return Response(NoteDetailSerializer(note).data)


class NoteBlocksApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, note_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can add blocks."}, status=status.HTTP_403_FORBIDDEN)
        serializer = BlockWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        next_index = NoteIndex.objects.filter(note_id=note).count()
        block = NoteBlock.objects.create(
            creator_id=note.creator_id,
            note_id=note,
            block_type=serializer.validated_data["block_type"],
            text=clean_block_string(serializer.validated_data.get("text", ""), serializer.validated_data["block_type"]),
            args=serializer.validated_data.get("args"),
            is_AI_generated=serializer.validated_data.get("is_AI_generated", False),
        )
        NoteIndex.objects.create(note_id=note, index=next_index, noteblock_id=block)
        sync_note_content_from_blocks(note)
        record_note_activity(note, block_word_count(block), HeatmapActivityTypeChoices.EDITED)
        return Response(NoteBlockSerializer(block).data, status=status.HTTP_201_CREATED)


class SingleBlockApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, block_id):
        block = get_object_or_404(NoteBlock.objects.select_related("note_id", "creator_id__user_id"), pk=block_id)
        if block.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can update this block."}, status=status.HTTP_403_FORBIDDEN)
        before_words = block_word_count(block)
        serializer = BlockWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field in ["block_type", "args", "is_AI_generated"]:
            if field in serializer.validated_data:
                setattr(block, field, serializer.validated_data[field])
        if "text" in serializer.validated_data:
            block.text = clean_block_string(serializer.validated_data["text"], block.block_type)
        block.save()
        sync_note_content_from_blocks(block.note_id)
        record_note_activity(
            block.note_id,
            max(abs(block_word_count(block) - before_words), block_word_count(block)),
            HeatmapActivityTypeChoices.EDITED,
        )
        return Response(NoteBlockSerializer(block).data)

    def delete(self, request, block_id):
        block = get_object_or_404(NoteBlock.objects.select_related("creator_id__user_id"), pk=block_id)
        if block.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can delete this block."}, status=status.HTTP_403_FORBIDDEN)
        note = block.note_id
        previous_words = block_word_count(block)
        block.delete()
        if note is not None:
            sync_note_content_from_blocks(note)
            record_note_activity(note, previous_words, HeatmapActivityTypeChoices.EDITED)
        return Response(status=status.HTTP_204_NO_CONTENT)


class ReorderBlocksApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, note_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can reorder blocks."}, status=status.HTTP_403_FORBIDDEN)
        serializer = ReorderSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        handles = {
            handle.noteblock_id_id: handle
            for handle in NoteIndex.objects.filter(note_id=note)
        }
        ordered_ids = serializer.validated_data["ordered_block_ids"]
        if set(handles.keys()) != set(ordered_ids):
            raise serializers.ValidationError("Reorder list must contain all block ids exactly once.")
        for index, block_id in enumerate(ordered_ids):
            handle = handles[block_id]
            handle.index = index
            handle.save(update_fields=["index"])
        sync_note_content_from_blocks(note)
        return Response({"message": "Blocks reordered."})


class NoteHistoryApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, note_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can view note history."}, status=status.HTTP_403_FORBIDDEN)
        return Response(NoteVersionSerializer(note.versions.all()[:12], many=True).data)


class NoteSnapshotApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, note_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can snapshot this note."}, status=status.HTTP_403_FORBIDDEN)
        version = snapshot_note_version(note, reason=request.data.get("reason", "manual"))
        return Response(NoteVersionSerializer(version).data, status=status.HTTP_201_CREATED)


class NoteRestoreApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, note_id, version_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can restore this note."}, status=status.HTTP_403_FORBIDDEN)
        version = get_object_or_404(NoteVersion, pk=version_id, note_id=note)
        snapshot_note_version(note, reason="before_restore")
        restore_note_version(note, version)
        replace_note_blocks(note, note.creator_id, note.content or note_markdown(note))
        return Response(NoteDetailSerializer(note).data)


class ActivityApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        notes = Note.objects.order_by("-last_edit")
        if request.user.is_authenticated:
            notes = notes.filter(creator_id__user_id=request.user)
        else:
            notes = notes.filter(course_id__is_default=True)
        return Response(NoteSummarySerializer(notes[:10], many=True).data)


class ActivityWeekApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        creator = ensure_creator(request.user)
        start_date = request.query_params.get("start_date")
        parsed_start = timezone.localdate()
        if start_date:
            try:
                parsed_start = datetime.fromisoformat(start_date).date()
            except ValueError:
                parsed_start = timezone.localdate()
        return Response(calendar_week_payload(creator, start_date=parsed_start))


class HeatmapApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        creator = ensure_creator(request.user)
        return Response(build_heatmap_payload(creator))


class PlannerEventListCreateApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        creator = ensure_creator(request.user)
        events = PlannerEvent.objects.filter(creator_id=creator).order_by("event_date", "title")
        return Response([planner_event_payload(event) for event in events])

    def post(self, request):
        creator = ensure_creator(request.user)
        serializer = PlannerEventWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        course = None
        if "course_id" in serializer.validated_data and serializer.validated_data["course_id"] is not None:
            course = get_object_or_404(Course, pk=serializer.validated_data["course_id"])
        event = PlannerEvent.objects.create(
            creator_id=creator,
            course_id=course,
            title=serializer.validated_data["title"],
            event_date=serializer.validated_data["event_date"],
            starts_at=serializer.validated_data.get("starts_at"),
            ends_at=serializer.validated_data.get("ends_at"),
            difficulty_weight=serializer.validated_data.get("difficulty_weight", 1),
            description=serializer.validated_data.get("description") or "",
        )
        normalize_planner_event_window(event)
        return Response(planner_event_payload(event), status=status.HTTP_201_CREATED)


class PlannerEventDetailApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, event_id):
        creator = ensure_creator(request.user)
        event = get_object_or_404(PlannerEvent, pk=event_id, creator_id=creator)
        serializer = PlannerEventWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field in ["title", "event_date", "starts_at", "ends_at", "difficulty_weight", "description"]:
            if field in serializer.validated_data:
                setattr(event, field, serializer.validated_data[field])
        if "course_id" in serializer.validated_data:
            course_id = serializer.validated_data["course_id"]
            event.course_id = get_object_or_404(Course, pk=course_id) if course_id is not None else None
        event.save()
        normalize_planner_event_window(event)
        return Response(planner_event_payload(event))


class NoteSessionListCreateApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        creator = ensure_creator(request.user)
        serializer = NoteSessionWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        note = get_object_or_404(Note, pk=serializer.validated_data["note_id"], creator_id=creator)
        started_at = serializer.validated_data.get("started_at") or timezone.now()
        session = NoteActivitySession.objects.create(
            creator_id=creator,
            note_id=note,
            title=serializer.validated_data.get("title") or note.title,
            summary=serializer.validated_data.get("summary") or (note.description or "")[:255],
            started_at=started_at,
            ended_at=serializer.validated_data.get("ended_at"),
        )
        return Response(note_session_payload(session), status=status.HTTP_201_CREATED)


class NoteSessionDetailApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, session_id):
        creator = ensure_creator(request.user)
        session = get_object_or_404(NoteActivitySession, pk=session_id, creator_id=creator)
        serializer = NoteSessionWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field in ["title", "summary", "started_at", "ended_at"]:
            if field in serializer.validated_data:
                setattr(session, field, serializer.validated_data[field])
        session.save()
        return Response(note_session_payload(session))


class CalendarFeedListCreateApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        creator = ensure_creator(request.user)
        return Response(CalendarFeedSerializer(CalendarFeed.objects.filter(creator_id=creator), many=True).data)

    def post(self, request):
        creator = ensure_creator(request.user)
        serializer = CalendarFeedWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        course = None
        if serializer.validated_data.get("course_id") is not None:
            course = get_object_or_404(Course, pk=serializer.validated_data["course_id"])
        feed = CalendarFeed.objects.create(
            creator_id=creator,
            course_id=course,
            title=serializer.validated_data["title"],
            source_kind=serializer.validated_data.get("source_kind", "I"),
            source_url=serializer.validated_data.get("source_url") or "",
            raw_ical=serializer.validated_data.get("raw_ical") or "",
            is_enabled=serializer.validated_data.get("is_enabled", True),
        )
        return Response(CalendarFeedSerializer(feed).data, status=status.HTTP_201_CREATED)


class CalendarFeedDetailApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, feed_id):
        creator = ensure_creator(request.user)
        feed = get_object_or_404(CalendarFeed, pk=feed_id, creator_id=creator)
        serializer = CalendarFeedWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field in ["title", "source_kind", "source_url", "raw_ical", "is_enabled"]:
            if field in serializer.validated_data:
                setattr(feed, field, serializer.validated_data[field])
        if "course_id" in serializer.validated_data:
            course_id = serializer.validated_data["course_id"]
            feed.course_id = get_object_or_404(Course, pk=course_id) if course_id is not None else None
        feed.save()
        return Response(CalendarFeedSerializer(feed).data)

    def delete(self, request, feed_id):
        creator = ensure_creator(request.user)
        feed = get_object_or_404(CalendarFeed, pk=feed_id, creator_id=creator)
        feed.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


def create_blocks_from_markdown(note: Note, creator, markdown: str) -> None:
    sections = split_markdown_sections(markdown, fallback_title=note.title)
    for index, section in enumerate(sections):
        block_type = NoteBlockTypeChoices.TITLE if index == 0 else NoteBlockTypeChoices.TEXT
        block = NoteBlock.objects.create(
            creator_id=creator,
            note_id=note,
            block_type=block_type,
            text=section["title"] if index == 0 else section["body"],
            is_AI_generated=False,
        )
        NoteIndex.objects.create(note_id=note, index=index, noteblock_id=block)


def markdown_from_blocks(blocks, fallback_title: str) -> str:
    if not blocks:
        return f"# {fallback_title}\n\n".strip()
    lines = []
    title_seen = False
    for block in blocks:
        block_type = block.get("block_type") or NoteBlockTypeChoices.TEXT
        text = (block.get("text") or "").strip()
        args = (block.get("args") or "").strip()
        if block_type == NoteBlockTypeChoices.TITLE:
            lines.append(f"# {text or fallback_title}")
            title_seen = True
        elif block_type == NoteBlockTypeChoices.SUBTITLE:
            lines.append(f"{args or '##'} {text}".strip())
        elif block_type == NoteBlockTypeChoices.URL:
            lines.append(f"[{text or args}]({args})" if args else text)
        elif block_type == NoteBlockTypeChoices.CODE:
            lines.append(f"```{args}\n{text}\n```".strip())
        elif block_type == NoteBlockTypeChoices.QUOTE:
            lines.append("\n".join([f"> {row}" for row in text.splitlines() if row.strip()]))
        elif block_type == NoteBlockTypeChoices.IMAGES:
            lines.append(f"![{text}]({args})" if args else text)
        elif block_type == NoteBlockTypeChoices.LIST:
            lines.extend([f"- {row}" for row in text.splitlines() if row.strip()])
        else:
            lines.append(text)
    if not title_seen:
        lines.insert(0, f"# {fallback_title}")
    return "\n\n".join([line for line in lines if line]).strip()


def create_blocks_from_payload(note: Note, creator, blocks) -> None:
    for index, block_payload in enumerate(blocks):
        block_type = block_payload.get("block_type") or NoteBlockTypeChoices.TEXT
        raw_text = block_payload.get("text") or ""
        block = NoteBlock.objects.create(
            creator_id=creator,
            note_id=note,
            block_type=block_type,
            text=clean_block_string(raw_text, block_type),
            args=block_payload.get("args") or None,
            is_AI_generated=bool(block_payload.get("is_AI_generated", False)),
        )
        NoteIndex.objects.create(note_id=note, index=index, noteblock_id=block)


@transaction.atomic
def replace_note_blocks(note: Note, creator, markdown: str) -> None:
    NoteIndex.objects.filter(note_id=note).delete()
    NoteBlock.objects.filter(note_id=note).delete()
    create_blocks_from_markdown(note, creator, markdown)


@transaction.atomic
def replace_note_blocks_from_payload(note: Note, creator, blocks) -> None:
    NoteIndex.objects.filter(note_id=note).delete()
    NoteBlock.objects.filter(note_id=note).delete()
    create_blocks_from_payload(note, creator, blocks)


def sync_note_content_from_blocks(note: Note) -> None:
    ordered_blocks = [
        {
            "block_type": handle.noteblock_id.block_type,
            "text": handle.noteblock_id.text or "",
            "args": handle.noteblock_id.args or "",
        }
        for handle in NoteIndex.objects.filter(note_id=note).select_related("noteblock_id").order_by("index")
    ]
    note.content = markdown_from_blocks(ordered_blocks, fallback_title=note.title)
    note.save(update_fields=["content", "last_edit"])


def normalize_planner_event_window(event: PlannerEvent) -> None:
    if event.starts_at is None:
        naive_start = datetime.combine(event.event_date, time(hour=12))
        event.starts_at = timezone.make_aware(naive_start)
    if event.ends_at is None or event.ends_at <= event.starts_at:
        event.ends_at = event.starts_at + timedelta(hours=1)
    event.event_date = timezone.localtime(event.starts_at).date()
    event.save(update_fields=["starts_at", "ends_at", "event_date", "last_edit"])


def split_markdown_sections(markdown: str, fallback_title: str):
    sections = []
    current_title = fallback_title
    current_lines = []
    for line in markdown.splitlines():
        if line.startswith("# ") or line.startswith("## "):
            if current_lines:
                sections.append({"title": current_title, "body": "\n".join(current_lines).strip()})
                current_lines = []
            current_title = line.lstrip("#").strip() or fallback_title
            continue
        current_lines.append(line)
    if current_lines or not sections:
        sections.append({"title": current_title, "body": "\n".join(current_lines).strip() or markdown.strip()})
    return sections
