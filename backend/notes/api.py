from django.db import transaction
from django.http import JsonResponse
from django.shortcuts import get_object_or_404

from rest_framework import permissions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from creators.utils import ensure_creator
from notechondria.utils import generate_unique_id

from .mark_down_parser import clean_block_string
from .models import Course, CourseMedia, Note, NoteBlock, NoteBlockTypeChoices, NoteIndex


def note_is_public(note: Note) -> bool:
    return bool(note.course_id and note.course_id.is_default)


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

    class Meta:
        model = Note
        fields = ["id", "title", "description", "excerpt", "last_edit", "date_created"]

    def get_excerpt(self, obj):
        first_text_block = (
            NoteBlock.objects.filter(note_id=obj)
            .exclude(text__isnull=True)
            .exclude(text__exact="")
            .order_by("date_created")
            .first()
        )
        if first_text_block is None:
            return obj.description or ""
        return first_text_block.text[:220]


class NoteDetailSerializer(NoteSummarySerializer):
    blocks = serializers.SerializerMethodField()
    course = serializers.SerializerMethodField()

    class Meta(NoteSummarySerializer.Meta):
        fields = NoteSummarySerializer.Meta.fields + ["course", "blocks"]

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
    course_id = serializers.IntegerField(required=False)
    title = serializers.CharField(max_length=100)
    description = serializers.CharField(allow_blank=True, required=False, allow_null=True)
    markdown = serializers.CharField(allow_blank=True, required=False)


class BlockWriteSerializer(serializers.Serializer):
    block_type = serializers.ChoiceField(choices=NoteBlockTypeChoices.choices)
    text = serializers.CharField(allow_blank=True, required=False)
    args = serializers.CharField(allow_blank=True, required=False, allow_null=True)
    is_AI_generated = serializers.BooleanField(required=False, default=False)


class ReorderSerializer(serializers.Serializer):
    ordered_block_ids = serializers.ListField(child=serializers.IntegerField(), min_length=1)


class FrontPageApiView(APIView):
    permission_classes = [permissions.AllowAny]

    @staticmethod
    def health(request):
        return JsonResponse({"status": "ok"})

    def get(self, request):
        default_course = Course.objects.filter(is_default=True).prefetch_related("media_items").first()
        if default_course is None:
            default_course = Course.objects.order_by("title").first()
        payload = {
            "default_course": CourseSerializer(default_course).data if default_course else None,
            "recent_notes": NoteSummarySerializer(
                Note.objects.filter(course_id=default_course).order_by("-last_edit")[:6],
                many=True,
            ).data if default_course else [],
        }
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
        return Response(NoteSummarySerializer(notes, many=True).data)


class NoteListCreateApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        course_id = request.query_params.get("course_id")
        notes = Note.objects.all()
        if course_id:
            notes = notes.filter(course_id_id=course_id)
        if request.user.is_authenticated:
            notes = notes.filter(creator_id__user_id=request.user)
        else:
            notes = notes.filter(course_id__is_default=True)
        return Response(NoteSummarySerializer(notes.order_by("-last_edit"), many=True).data)

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
        )
        create_blocks_from_markdown(
            note=note,
            creator=creator,
            markdown=serializer.validated_data.get("markdown") or note.description or note.title,
        )
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
        for field in ["title", "description"]:
            if field in serializer.validated_data:
                setattr(note, field, serializer.validated_data[field])
        note.save()
        if "markdown" in serializer.validated_data:
            replace_note_blocks(note, note.creator_id, serializer.validated_data["markdown"])
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
        return Response(NoteBlockSerializer(block).data, status=status.HTTP_201_CREATED)


class SingleBlockApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, block_id):
        block = get_object_or_404(NoteBlock.objects.select_related("note_id", "creator_id__user_id"), pk=block_id)
        if block.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can update this block."}, status=status.HTTP_403_FORBIDDEN)
        serializer = BlockWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field in ["block_type", "args", "is_AI_generated"]:
            if field in serializer.validated_data:
                setattr(block, field, serializer.validated_data[field])
        if "text" in serializer.validated_data:
            block.text = clean_block_string(serializer.validated_data["text"], block.block_type)
        block.save()
        return Response(NoteBlockSerializer(block).data)

    def delete(self, request, block_id):
        block = get_object_or_404(NoteBlock.objects.select_related("creator_id__user_id"), pk=block_id)
        if block.creator_id.user_id_id != request.user.id:
            return Response({"detail": "Only the owner can delete this block."}, status=status.HTTP_403_FORBIDDEN)
        block.delete()
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
        return Response({"message": "Blocks reordered."})


class ActivityApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        notes = Note.objects.order_by("-last_edit")
        if request.user.is_authenticated:
            notes = notes.filter(creator_id__user_id=request.user)
        else:
            notes = notes.filter(course_id__is_default=True)
        return Response(NoteSummarySerializer(notes[:10], many=True).data)


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


@transaction.atomic
def replace_note_blocks(note: Note, creator, markdown: str) -> None:
    NoteIndex.objects.filter(note_id=note).delete()
    NoteBlock.objects.filter(note_id=note).delete()
    create_blocks_from_markdown(note, creator, markdown)


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
