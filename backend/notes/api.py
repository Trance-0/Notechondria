import json
import io
import logging
import re
from difflib import SequenceMatcher
from datetime import datetime, timedelta, time

from django.conf import settings
from django.core.management import call_command
from django.db import transaction
from django.db.models import Count, Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.text import slugify

from rest_framework import permissions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from creators.utils import ensure_creator, ensure_creator_avatar
from notechondria.utils import generate_unique_id

# Module-level logger for note CRUD + sync diagnostics. Every log line
# emitted through this logger must follow AGENTS.md §1.7:
# "<consequence>: <module>/<process> — <cause>". 401/403 already get a
# shaped line from notechondria.drf_exception_handler; this logger is
# for post-auth note-editor flow events (create / update / delete /
# attachment / version) so operators can trace why a save fell over.
logger = logging.getLogger("notechondria.notes")

from courses.models import (
    Course,
    CourseMedia,
    CourseOperationLog,
    CourseOperationTypeChoices,
    CourseSubscription,
)
from planner.models import (
    CalendarFeed,
    HeatmapActivityTypeChoices,
    PlannerEvent,
)

from .mark_down_parser import clean_block_string
from .models import (
    Note,
    NoteActivitySession,
    NoteAttachment,
    NoteBlock,
    NoteVersion,
    NoteBlockTypeChoices,
    NoteIndex,
    RecycleBinEntry,
)
from .services import (
    DEFAULT_CALENDAR_RANGE_DAYS,
    block_word_count,
    build_heatmap_payload,
    calendar_week_payload,
    normalize_calendar_url,
    note_word_count,
    note_markdown,
    note_preview_lines,
    note_session_payload,
    planner_event_payload,
    CourseGitError,
    apply_course_git_binding,
    course_git_payload,
    record_note_activity,
    restore_note_version,
    snapshot_note_version,
    summarize_calendar_feed,
    unlink_course_git,
    version_label,
)


def note_is_public(note: Note) -> bool:
    # Public visibility requires the explicit ``is_public=True`` flag
    # set per-note. Pre-0.1.83 promoted "default course" notes to the
    # public feed automatically; that promotion was removed there and
    # nothing replaces it here. Notes whose ``course_id`` is NULL (the
    # uncategorized bucket) follow the exact same rule — only the
    # per-note flag matters.
    return bool(note.is_public)


def absolute_media_url(request, raw_url: str) -> str:
    if not raw_url:
        return ""
    if raw_url.startswith("http://") or raw_url.startswith("https://"):
        # When R2/S3 storage is configured MEDIA_URL is an absolute URL
        # (e.g. https://r2-domain.com/media/).  Rewrite those to same-origin
        # /media/ paths so the frontend can load them without CORS issues
        # (Flutter Web CanvasKit uses fetch(), not <img> tags).
        media_url = getattr(settings, "MEDIA_URL", "/media/")
        if media_url.startswith("http") and raw_url.startswith(media_url):
            raw_url = "/media/" + raw_url[len(media_url):]
        else:
            return raw_url
    if request is None:
        return raw_url
    host = (
        request.META.get("HTTP_X_FORWARDED_HOST")
        or request.META.get("HTTP_HOST")
        or request.get_host()
    )
    scheme = request.META.get("HTTP_X_FORWARDED_PROTO") or request.scheme
    normalized = raw_url if raw_url.startswith("/") else f"/{raw_url}"
    if host:
        return f"{scheme}://{host}{normalized}"
    return request.build_absolute_uri(normalized)


def creator_summary_payload(creator, request):
    """Author card emitted on every public-facing note / comment surface.

    Avatar resolution mirrors ``creators.api.auth_payload``: a fresh
    Casdoor mirror in our own storage is the effective avatar (Casdoor
    serves without CORS headers → Flutter web can't render it
    cross-origin); otherwise the Casdoor URL, then the local upload.

    Performance contract (0.1.185): this runs **per row** on every list
    surface — it must do ZERO storage or network I/O and ZERO writes.
    The old version called ``ensure_creator_avatar`` (an R2
    ``storage.exists()`` HEAD + potential write) per note row: a
    193-note course spent ~15 s in storage round-trips for one author.
    Payloads are additionally memoized per request via
    ``author_payload_cache`` since list rows overwhelmingly share
    authors.
    """
    if creator is None:
        return None
    cache = getattr(request, "_author_payload_cache", None) if request else None
    if cache is not None and creator.id in cache:
        return cache[creator.id]
    username = creator.user_id.username if creator.user_id_id else "unknown"
    display_name = (
        (creator.display_name or "").strip()
        or (
            f"{creator.user_id.first_name} {creator.user_id.last_name}".strip()
            if creator.user_id_id
            else ""
        )
        or username
    )
    avatar_url = _avatar_cache_bust(creator.avatar_url, creator)
    stored_url = absolute_media_url(
        request, creator.image.url if creator.image and creator.image.name else "",
    )
    from creators.utils import mirrored_avatar_is_fresh

    image_url = (
        stored_url
        if mirrored_avatar_is_fresh(creator)
        else (avatar_url or stored_url)
    )
    payload = {
        "id": creator.id,
        "username": username,
        "display_name": display_name,
        "image_url": image_url,
        "avatar_url": avatar_url,
    }
    if request is not None:
        if cache is None:
            cache = {}
            request._author_payload_cache = cache
        cache[creator.id] = payload
    return payload


def _avatar_cache_bust(url: str, creator) -> str:
    """Mirror of ``creators.api.avatar_cache_bust``. Re-implemented in
    this module to avoid pulling the entire ``creators.api`` import
    surface (which would re-introduce the ``notes`` ⇄ ``creators``
    cycle the apps were carefully split to avoid)."""
    if not url:
        return url
    synced = getattr(creator, "casdoor_profile_synced_at", None)
    if synced is None:
        return url
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}v={int(synced.timestamp())}"


def deleted_note_summary_payload(entry: RecycleBinEntry, request):
    payload = NoteSummarySerializer(entry.note_id, context={"request": request}).data
    payload["deleted_at"] = entry.deleted_at.isoformat()
    payload["recycle_bin_entry_id"] = entry.id
    return payload


def active_subscription_map(creator):
    if creator is None:
        return {}
    subscriptions = CourseSubscription.objects.filter(
        creator_id=creator,
        is_active=True,
    ).select_related("course_id")
    return {subscription.course_id_id: subscription for subscription in subscriptions}


def course_sort_key(course, subscription_map):
    # 0.1.120: the special "Inbox is pinned first" rule was retired
    # along with ``Course.is_default``. The synthetic uncategorized
    # bucket is rendered client-side as a virtual entry above the
    # actual Course rows; ordering of real categories now uses the
    # user-set ``sort_order`` first, then subscription recency, then
    # title for ties.
    if course.sort_order:
        return (1, course.sort_order, 0, course.title.lower())
    subscription = subscription_map.get(course.id)
    if subscription is not None:
        opened = subscription.last_opened_at or subscription.subscribed_at or timezone.now()
        return (2, -opened.timestamp(), 0, course.title.lower())
    return (3, 0, 0, course.title.lower())


def append_course_operation(creator, course, operation_type, metadata=None):
    CourseOperationLog.objects.create(
        creator_id=creator,
        course_id=course,
        operation_type=operation_type,
        metadata_json="" if not metadata else json.dumps(metadata, sort_keys=True),
    )


def arm_course_sync(note):
    """Arm the lazy-sync debounce when a note in a bound, sync-enabled
    course is edited (the app is a repo text editor; edits accrue and the
    push fires after the idle timeout). No-op for unbound courses."""
    course = getattr(note, "course_id", None)
    if course is None:
        return
    from courses.git_service import mark_course_pending

    mark_course_pending(course)


def unique_course_slug(title: str, fallback: str = "course") -> str:
    base = slugify(title)[:100] or fallback
    candidate = base
    counter = 2
    while Course.objects.filter(slug=candidate).exists():
        suffix = f"-{counter}"
        candidate = f"{base[: max(1, 120 - len(suffix))]}{suffix}"
        counter += 1
    return candidate


def note_search_score(note: Note, query: str):
    normalized = query.strip().lower()
    if not normalized:
        return (1.0, 1.0)
    title = (note.title or "").lower()
    description = (note.description or "").lower()
    content = (note.content or "").lower()
    searchable = " ".join([title, description, content]).strip()
    tokens = [token for token in re.split(r"\s+", normalized) if token]
    exact_hits = sum(1 for token in tokens if token in searchable)
    title_hits = sum(1 for token in tokens if token in title)
    fuzzy = max(
        SequenceMatcher(None, normalized, title).ratio() if title else 0.0,
        SequenceMatcher(None, normalized, description).ratio() if description else 0.0,
        SequenceMatcher(None, normalized, content[:400]).ratio() if content else 0.0,
        SequenceMatcher(None, normalized, searchable[:500]).ratio() if searchable else 0.0,
    )
    if exact_hits == 0 and fuzzy < 0.45:
        return None
    score = (exact_hits * 10.0) + (title_hits * 5.0) + fuzzy
    return (score, fuzzy)


def can_access_note(request, note: Note) -> bool:
    if note_is_public(note):
        return True
    if not (request.user and request.user.is_authenticated):
        return False
    if note.creator_id.user_id_id == request.user.id:
        return True
    # 0.1.179: an authenticated user with an ACTIVE subscription to the
    # note's course may read its private notes too — this is what makes a
    # shared per-note URL work for subscribed course content. Write access
    # is still owner-only (checked separately at each write view).
    if note.course_id_id:
        return CourseSubscription.objects.filter(
            course_id=note.course_id_id,
            creator_id__user_id=request.user.id,
            is_active=True,
        ).exists()
    return False


def require_note_access(request, note_id: int) -> Note:
    note = get_object_or_404(
        Note.objects.select_related("course_id", "creator_id__user_id").filter(deleted_at__isnull=True),
        pk=note_id,
    )
    if not can_access_note(request, note):
        raise serializers.ValidationError(
            "Note access denied: "
            "Backend.Notes.Notes/access_check \u2014 "
            "note is private and the requester is not its owner."
        )
    return note


class CourseMediaSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = CourseMedia
        fields = ["id", "title", "description", "source", "image_url"]

    def get_image_url(self, obj):
        request = self.context.get("request") if self.context else None
        return absolute_media_url(request, obj.image.url if obj.image else "")


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
        request = self.context.get("request") if self.context else None
        return absolute_media_url(request, obj.image.url if obj.image else "")


class NoteSummarySerializer(serializers.ModelSerializer):
    uuid = serializers.UUIDField(read_only=True)
    excerpt = serializers.SerializerMethodField()
    editor_mode = serializers.CharField(read_only=True)
    note_type = serializers.CharField(read_only=True)
    preview_lines = serializers.SerializerMethodField()
    author = serializers.SerializerMethodField()
    course = serializers.SerializerMethodField()
    source_note_uuid = serializers.SerializerMethodField()
    cover_image_url = serializers.SerializerMethodField()

    name = serializers.CharField(read_only=True)
    git_path = serializers.CharField(read_only=True)
    module = serializers.CharField(read_only=True)

    class Meta:
        model = Note
        fields = [
            "id",
            "uuid",
            "name",
            "git_path",
            "module",
            "title",
            "description",
            "excerpt",
            "preview_lines",
            "editor_mode",
            "note_type",
            "is_public",
            "last_edit",
            "date_created",
            "course_id",
            "course",
            "author",
            "source_note_uuid",
            "cover_image_url",
        ]

    def get_excerpt(self, obj):
        # Prefer note.content (always populated on save) to avoid an extra
        # NoteBlock query per row — this is the main N+1 hot-spot.
        if obj.content:
            lines = obj.content.strip()
            if lines.startswith("# "):
                lines = lines.split("\n", 1)[-1].strip()
            return lines[:220]
        if obj.description:
            return obj.description[:220]
        return ""

    def get_preview_lines(self, obj):
        return note_preview_lines(obj)

    def get_author(self, obj):
        request = self.context.get("request") if self.context else None
        return creator_summary_payload(obj.creator_id, request)

    def get_course(self, obj):
        if obj.course_id is None:
            return None
        return {
            "id": obj.course_id.id,
            "title": obj.course_id.title,
            "slug": obj.course_id.slug,
        }

    def get_source_note_uuid(self, obj):
        if obj.source_note is None:
            return None
        return str(obj.source_note.uuid)

    def get_cover_image_url(self, obj):
        request = self.context.get("request") if self.context else None
        return absolute_media_url(
            request, obj.cover_image.url if obj.cover_image else ""
        )


class NoteDetailSerializer(NoteSummarySerializer):
    blocks = serializers.SerializerMethodField()
    content = serializers.CharField(read_only=True)
    metadata_json = serializers.CharField(read_only=True)
    custom_meta = serializers.CharField(read_only=True)
    # `git_path` / `name` are inherited from NoteSummarySerializer.

    class Meta(NoteSummarySerializer.Meta):
        fields = NoteSummarySerializer.Meta.fields + [
            "blocks",
            "content",
            "metadata_json",
            "custom_meta",
        ]

    def get_blocks(self, obj):
        ordered_blocks = [
            handle.noteblock_id
            for handle in NoteIndex.objects.filter(note_id=obj).select_related("noteblock_id").order_by("index")
        ]
        return NoteBlockSerializer(
            ordered_blocks,
            many=True,
            context=self.context,
        ).data


class CourseSerializer(serializers.ModelSerializer):
    cover_image_url = serializers.SerializerMethodField()
    recent_notes = serializers.SerializerMethodField()
    owner = serializers.SerializerMethodField()
    subscriber_count = serializers.SerializerMethodField()
    is_subscribed = serializers.SerializerMethodField()
    is_private_subscription = serializers.SerializerMethodField()
    last_opened_at = serializers.SerializerMethodField()
    media = CourseMediaSerializer(source="media_items", many=True, read_only=True)
    git = serializers.SerializerMethodField()

    class Meta:
        model = Course
        fields = [
            "id",
            "client_course_id",
            "slug",
            "title",
            "description",
            "cover_image_url",
            "icon",
            "color_hue",
            "sort_order",
            "owner",
            "subscriber_count",
            "is_subscribed",
            "is_private_subscription",
            "last_opened_at",
            "recent_notes",
            "media",
            "git",
        ]

    def get_git(self, obj):
        # Git binding is private to the course owner; subscribers and
        # anonymous viewers get null so the repo/branch never leaks.
        request = self.context.get("request") if self.context else None
        if (
            request is None
            or not request.user.is_authenticated
            or obj.creator_id is None
            or obj.creator_id.user_id_id != request.user.id
        ):
            return None
        return course_git_payload(obj)

    def get_cover_image_url(self, obj):
        request = self.context.get("request") if self.context else None
        return absolute_media_url(request, obj.cover_image.url if obj.cover_image else "")

    def get_recent_notes(self, obj):
        request = self.context.get("request") if self.context else None
        recent_notes = obj.notes.filter(deleted_at__isnull=True).order_by("-last_edit")
        if (
            request is None
            or not request.user.is_authenticated
            or obj.creator_id is None
            or obj.creator_id.user_id_id != request.user.id
        ):
            # Non-owners only see notes explicitly flagged ``is_public=True``.
            # Pre-0.1.83 promoted "default course" notes to public; that
            # rule was removed there and never reinstated.
            recent_notes = recent_notes.filter(is_public=True)
        return NoteSummarySerializer(
            recent_notes[:5],
            many=True,
            context=self.context,
        ).data

    def get_owner(self, obj):
        request = self.context.get("request") if self.context else None
        return creator_summary_payload(obj.creator_id, request)

    def get_subscriber_count(self, obj):
        if hasattr(obj, "_subscriber_count"):
            return obj._subscriber_count
        return CourseSubscription.objects.filter(course_id=obj, is_active=True).count()

    def get_is_subscribed(self, obj):
        subscription_map = self.context.get("subscription_map") if self.context else None
        if subscription_map is None:
            return False
        return obj.id in subscription_map

    def get_is_private_subscription(self, obj):
        subscription_map = self.context.get("subscription_map") if self.context else None
        subscription = subscription_map.get(obj.id) if subscription_map else None
        return bool(subscription and subscription.is_private)

    def get_last_opened_at(self, obj):
        subscription_map = self.context.get("subscription_map") if self.context else None
        subscription = subscription_map.get(obj.id) if subscription_map else None
        if subscription is None or subscription.last_opened_at is None:
            return None
        return subscription.last_opened_at.isoformat()


class CourseWriteSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=120)
    description = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    client_course_id = serializers.CharField(required=False, allow_blank=True, max_length=64)
    icon = serializers.IntegerField(required=False, allow_null=True)
    color_hue = serializers.IntegerField(
        required=False, allow_null=True, min_value=0, max_value=359
    )


class NoteWriteSerializer(serializers.Serializer):
    course_id = serializers.IntegerField(required=False, allow_null=True)
    title = serializers.CharField(max_length=100)
    description = serializers.CharField(allow_blank=True, required=False, allow_null=True)
    markdown = serializers.CharField(allow_blank=True, required=False)
    content = serializers.CharField(allow_blank=True, required=False)
    metadata_json = serializers.CharField(allow_blank=True, required=False)
    custom_meta = serializers.CharField(allow_blank=True, required=False)
    is_public = serializers.BooleanField(required=False)
    client_draft_id = serializers.CharField(required=False, allow_blank=True, max_length=64)
    blocks = serializers.ListField(child=serializers.DictField(), required=False)
    editor_mode = serializers.ChoiceField(choices=[("G", "gfm"), ("B", "blocks"), ("P", "plain_text")], required=False)
    note_type = serializers.ChoiceField(choices=[("N", "Normal"), ("C", "Comment")], required=False)
    source_note_uuid = serializers.UUIDField(required=False, allow_null=True)


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
    is_completed = serializers.BooleanField(required=False)
    completed_at = serializers.DateTimeField(required=False, allow_null=True)
    recurrence_freq = serializers.ChoiceField(
        choices=[("N", "none"), ("W", "weekly"), ("M", "monthly"), ("Y", "yearly")],
        required=False,
    )
    recurrence_interval = serializers.IntegerField(min_value=1, required=False)
    recurrence_end_date = serializers.DateField(required=False, allow_null=True)
    recurrence_count = serializers.IntegerField(min_value=1, required=False, allow_null=True)


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
        creator = ensure_creator(request.user) if request.user.is_authenticated else None
        subscription_map = active_subscription_map(creator)
        # 0.1.180: the "recent public courses" carousel only surfaces
        # courses that actually have public content. Previously it listed
        # EVERY course row, so stale personal buckets (e.g. the pre-0.1.120
        # editor "Inbox" template) leaked onto everyone's front page.
        courses = list(
            Course.objects.select_related("creator_id__user_id")
            .prefetch_related("media_items")
            .annotate(
                _subscriber_count=Count(
                    "subscriptions", filter=Q(subscriptions__is_active=True),
                ),
                _public_note_count=Count(
                    "notes",
                    filter=Q(notes__is_public=True, notes__deleted_at__isnull=True),
                ),
            )
            .filter(_public_note_count__gt=0)
        )
        courses.sort(key=lambda course: course_sort_key(course, subscription_map))
        carousel_courses = courses[:6]
        # 0.1.120: with `Course.is_default` removed, the carousel's
        # "default" slot is just the top-sorted course (or None when
        # the user has no categories yet — the SPA falls back to its
        # synthetic uncategorized bucket).
        default_course = carousel_courses[0] if carousel_courses else None
        recommended_notes = Note.objects.filter(
            is_public=True,
            deleted_at__isnull=True,
        ).select_related("course_id", "creator_id__user_id").order_by("-last_edit")[:12]
        serializer_context = {
            "request": request,
            "subscription_map": subscription_map,
        }
        carousel_data = CourseSerializer(carousel_courses, many=True, context=serializer_context).data
        recommended_data = NoteSummarySerializer(
            recommended_notes, many=True, context={"request": request},
        ).data
        payload = {
            "default_course": CourseSerializer(default_course, context=serializer_context).data if default_course else None,
            "carousel_courses": carousel_data,
            "recent_notes": recommended_data[:6],
            "recommended_notes": recommended_data,
            "collections": carousel_data,
        }
        if request.user.is_authenticated:
            # A full year of past activity (plus ~4 weeks of planned load)
            # so a wide window can render more history and fill the row;
            # the frontend trims to the most-recent weeks that fit.
            payload["heatmap"] = build_heatmap_payload(
                ensure_creator(request.user), days_before=364, days_after=28
            )
            payload["upcoming_events"] = [
                planner_event_payload(event)
                for event in PlannerEvent.objects.filter(
                    creator_id=ensure_creator(request.user),
                    event_date__gte=timezone.localdate(),
                    is_completed=False,
                ).order_by("event_date", "title")[:8]
            ]
        return Response(payload)


class CourseListApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        creator = ensure_creator(request.user) if request.user.is_authenticated else None
        # Lazy-on-request sync: flush any of this owner's bound courses
        # whose debounce has elapsed. Best-effort — never blocks the list.
        if creator is not None:
            try:
                from courses.git_service import flush_due_course_syncs

                flush_due_course_syncs(creator)
            except Exception:  # noqa: BLE001 - sync must never break course listing
                logger.exception("Lazy course-git flush failed during course list")
        subscription_map = active_subscription_map(creator)
        courses = list(
            Course.objects.select_related("creator_id__user_id")
            .prefetch_related("media_items")
            .annotate(_subscriber_count=Count(
                "subscriptions", filter=Q(subscriptions__is_active=True),
            ))
            .all()
        )
        courses.sort(key=lambda course: course_sort_key(course, subscription_map))
        return Response(
            CourseSerializer(
                courses,
                many=True,
                context={"request": request, "subscription_map": subscription_map},
            ).data
        )

    def post(self, request):
        if not request.user.is_authenticated:
            return Response(
                {"detail": (
                    "Cannot create category: "
                    "Backend.Notes.Courses/create \u2014 "
                    "request has no authenticated user."
                )},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        creator = ensure_creator(request.user)
        serializer = CourseWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        title = serializer.validated_data["title"].strip()
        description = serializer.validated_data.get("description") or ""
        client_course_id = serializer.validated_data.get("client_course_id") or None
        existing = None
        if client_course_id:
            existing = Course.objects.filter(
                creator_id=creator,
                client_course_id=client_course_id,
            ).first()
        icon = serializer.validated_data.get("icon")
        # Name-uniqueness guard. Categories are user-scoped; the
        # same creator may not have two courses with the same
        # title (case-insensitive). The upsert path skips the
        # check against itself when only renaming, so we exclude
        # `existing.id`.
        #
        # 0.1.120: the special "Inbox is globally unique per user;
        # silently get-or-create on collision" branch was retired
        # along with ``Course.is_default``. "Inbox" is no longer
        # reserved \u2014 if the user really wants a category named
        # Inbox they get the standard 400-on-duplicate behaviour.
        # The actual uncategorized bucket lives entirely on the
        # frontend (any Note with ``course_id IS NULL``).
        duplicate_qs = Course.objects.filter(
            creator_id=creator,
            title__iexact=title,
        )
        if existing is not None:
            duplicate_qs = duplicate_qs.exclude(pk=existing.pk)
        duplicate = duplicate_qs.first()
        if duplicate is not None:
            return Response(
                {"detail": (
                    "Cannot create category: "
                    "Backend.Notes.Courses/create \u2014 "
                    f"a category named '{title}' already exists for this user."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if existing is not None:
            existing.title = title
            existing.description = description
            update_fields = ["title", "description", "last_edit"]
            if "icon" in serializer.validated_data:
                existing.icon = icon
                update_fields.append("icon")
            existing.save(update_fields=update_fields)
            course = existing
            response_status = status.HTTP_200_OK
        else:
            course = Course.objects.create(
                creator_id=creator,
                client_course_id=client_course_id,
                slug=unique_course_slug(title, fallback="local-course"),
                title=title,
                description=description,
                icon=icon,
            )
            response_status = status.HTTP_201_CREATED
        subscription_map = active_subscription_map(creator)
        return Response(
            CourseSerializer(
                course,
                context={"request": request, "subscription_map": subscription_map},
            ).data,
            status=response_status,
        )


class CourseDetailApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, course_id):
        creator = ensure_creator(request.user) if request.user.is_authenticated else None
        subscription_map = active_subscription_map(creator)
        course = get_object_or_404(
            Course.objects.select_related("creator_id__user_id").prefetch_related("media_items"),
            pk=course_id,
        )
        return Response(
            CourseSerializer(
                course,
                context={"request": request, "subscription_map": subscription_map},
            ).data
        )

    def patch(self, request, course_id):
        if not request.user.is_authenticated:
            return Response(
                {"detail": (
                    "Cannot update category: "
                    "Backend.Notes.Courses/update \u2014 "
                    "request has no authenticated user."
                )},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        creator = ensure_creator(request.user)
        course = get_object_or_404(Course, pk=course_id)
        if course.creator_id_id != creator.id:
            return Response(
                {"detail": (
                    "Cannot update category: "
                    "Backend.Notes.Courses/update \u2014 "
                    "category is owned by a different creator."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        # 0.1.120: name-based protection of "Inbox" was retired.
        # Categories are now freely renameable \u2014 duplicate-title
        # collisions still 400 (categories are case-insensitively
        # unique per creator), but no title is reserved.
        serializer = CourseWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        new_title = (
            serializer.validated_data["title"].strip()
            if "title" in serializer.validated_data
            else None
        )
        if new_title is not None and new_title != course.title:
            duplicate = (
                Course.objects.filter(creator_id=creator, title__iexact=new_title)
                .exclude(pk=course.pk)
                .exists()
            )
            if duplicate:
                return Response(
                    {"detail": (
                        "Cannot update category: "
                        "Backend.Notes.Courses/update \u2014 "
                        f"a category named '{new_title}' already exists."
                    )},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            course.title = new_title
        if "description" in serializer.validated_data:
            course.description = serializer.validated_data.get("description") or ""
        if "icon" in serializer.validated_data:
            course.icon = serializer.validated_data.get("icon")
        if "color_hue" in serializer.validated_data:
            course.color_hue = serializer.validated_data.get("color_hue")
        course.save()
        subscription_map = active_subscription_map(creator)
        return Response(
            CourseSerializer(
                course,
                context={"request": request, "subscription_map": subscription_map},
            ).data
        )

    def delete(self, request, course_id):
        if not request.user.is_authenticated:
            return Response(
                {"detail": (
                    "Cannot delete category: "
                    "Backend.Notes.Courses/delete \u2014 "
                    "request has no authenticated user."
                )},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        creator = ensure_creator(request.user)
        course = get_object_or_404(Course, pk=course_id)
        if course.creator_id_id != creator.id:
            return Response(
                {"detail": (
                    "Cannot delete category: "
                    "Backend.Notes.Courses/delete \u2014 "
                    "category is owned by a different creator."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        # 0.1.120: any category may be deleted \u2014 including one titled
        # "Inbox", which is no longer reserved. Notes whose category is
        # deleted fall to ``course_id IS NULL`` automatically because
        # ``Note.course_id`` is ``on_delete=SET_NULL``; the SPA's
        # synthetic uncategorized bucket picks them up. No manual
        # reassignment needed.
        course.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class CourseGitWriteSerializer(serializers.Serializer):
    """Shapes the git-binding payload; the repo `owner/name` form is
    validated in the service (`apply_course_git_binding`)."""

    repo = serializers.CharField(max_length=255, required=False, allow_blank=True)
    branch = serializers.CharField(max_length=255, required=False, allow_blank=True)
    sync_enabled = serializers.BooleanField(required=False)
    sync_timeout_minutes = serializers.IntegerField(
        min_value=1, max_value=1440, required=False
    )


class CourseGitBindingApiView(APIView):
    """Owner-only CRUD for a course's GitHub binding (the backend stays the
    source of truth; this only stores where to mirror to and how eagerly).

    - GET returns the binding config.
    - PUT binds / updates it (repo, branch, sync toggle, debounce minutes)
      and, when a repo is set, arms the lazy-sync debounce.
    - DELETE unlinks (clears the repo and disables sync).

    Every mutation writes a CourseOperationLog row so the owner gets the
    effective import/bind/unlink log they asked for."""

    permission_classes = [permissions.IsAuthenticated]

    def _owned_course(self, request, course_id):
        creator = ensure_creator(request.user)
        course = get_object_or_404(Course, pk=course_id)
        if course.creator_id_id != creator.id:
            return creator, course, Response(
                {"detail": (
                    "Cannot change git binding: "
                    "Backend.Notes.Courses.Git/bind — "
                    "category is owned by a different creator."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        return creator, course, None

    def get(self, request, course_id):
        _creator, course, error = self._owned_course(request, course_id)
        if error is not None:
            return error
        return Response(course_git_payload(course))

    def put(self, request, course_id):
        creator, course, error = self._owned_course(request, course_id)
        if error is not None:
            return error
        serializer = CourseGitWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        # Only forward fields the client actually sent (so a bare tweak of
        # one field doesn't reset the others).
        kwargs = {key: data[key] for key in (
            "repo", "branch", "sync_enabled", "sync_timeout_minutes",
        ) if key in data}
        try:
            payload = apply_course_git_binding(creator, course, **kwargs)
        except CourseGitError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(payload)

    def delete(self, request, course_id):
        creator, course, error = self._owned_course(request, course_id)
        if error is not None:
            return error
        return Response(unlink_course_git(creator, course))


class CourseGitImportApiView(APIView):
    """Owner-only: pull the bound repo's markdown into this course's notes
    via the course-repo adapter. Idempotent (notes matched by git_path)."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, course_id):
        from courses.git_service import CourseGitServiceError, import_course_from_repo

        creator = ensure_creator(request.user)
        course = get_object_or_404(Course, pk=course_id)
        if course.creator_id_id != creator.id:
            return Response(
                {"detail": (
                    "Cannot import: Backend.Notes.Courses.Git/import — "
                    "category is owned by a different creator."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        try:
            summary = import_course_from_repo(course)
        except CourseGitServiceError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(summary)


class CourseGitSyncApiView(APIView):
    """Owner-only: explicitly push this course's notes to its bound repo
    now (the "sync now" button). Lazy sync also fires this on idle."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, course_id):
        from courses.git_service import CourseGitServiceError, sync_course_to_repo

        creator = ensure_creator(request.user)
        course = get_object_or_404(Course, pk=course_id)
        if course.creator_id_id != creator.id:
            return Response(
                {"detail": (
                    "Cannot sync: Backend.Notes.Courses.Git/sync — "
                    "category is owned by a different creator."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        try:
            summary = sync_course_to_repo(course)
        except CourseGitServiceError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(summary)


class CourseReorderApiView(APIView):
    """Accepts an ordered list of course ids and rewrites their `sort_order`
    so the user's preferred arrangement survives across sessions."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        creator = ensure_creator(request.user)
        ids = request.data.get("course_ids")
        if not isinstance(ids, list):
            return Response(
                {"detail": "`course_ids` must be a list of integers."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # 0.1.120: every owned category is reorderable. The synthetic
        # uncategorized bucket lives entirely on the frontend and isn't
        # represented as a Course row, so it never shows up in this
        # query and the SPA pins it client-side.
        owned = {
            c.id: c
            for c in Course.objects.filter(creator_id=creator)
        }
        # Tolerate garbage entries: non-int-ish items are skipped silently so a
        # transient client bug can't brick a reorder request. Only ids that map
        # to courses owned by this creator survive.
        new_order = []
        seen = set()
        for raw in ids:
            try:
                course_id = int(raw)
            except (TypeError, ValueError):
                continue
            if course_id in owned and course_id not in seen:
                new_order.append(course_id)
                seen.add(course_id)
        with transaction.atomic():
            # Rewrite sort_order for every course in the list. Start at 1 so
            # zero remains the "unset" marker for course_sort_key.
            for index, course_id in enumerate(new_order, start=1):
                course = owned[course_id]
                course.sort_order = index
                course.save(update_fields=["sort_order", "last_edit"])
        subscription_map = active_subscription_map(creator)
        courses = list(
            Course.objects.select_related("creator_id__user_id")
            .prefetch_related("media_items")
            .filter(creator_id=creator)
        )
        courses.sort(key=lambda course: course_sort_key(course, subscription_map))
        return Response(
            CourseSerializer(
                courses,
                many=True,
                context={"request": request, "subscription_map": subscription_map},
            ).data
        )


class CourseNotesApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, course_id):
        course = get_object_or_404(Course, pk=course_id)
        # 0.1.188: imported courses read top-to-bottom. `sort_order` is 0
        # for natively-created notes, so those still fall back to pure
        # recency via the secondary key (unchanged behaviour).
        notes = (
            course.notes.filter(deleted_at__isnull=True)
            .select_related("course_id", "creator_id__user_id")
            .order_by("sort_order", "-last_edit")
        )
        if (
            not request.user.is_authenticated
            or course.creator_id is None
            or course.creator_id.user_id_id != request.user.id
        ):
            # Non-owners only see notes flagged ``is_public=True``.
            # Pre-0.1.83 promoted "default-course" notes to the public
            # feed; that rule was removed there and never reinstated.
            notes = notes.filter(is_public=True)
        # 0.1.185: lazy loading for large (e.g. git-imported) courses.
        # With `limit` the response is a page envelope; without it the
        # legacy bare list is preserved so older clients keep working.
        limit = request.query_params.get("limit")
        if limit is not None:
            try:
                page_size = max(1, min(int(limit), 100))
                offset = max(0, int(request.query_params.get("offset", "0") or 0))
            except ValueError:
                return Response(
                    {"detail": (
                        "Cannot list category notes: "
                        "Backend.Notes.Courses/notes — "
                        "`limit`/`offset` must be integers."
                    )},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            total = notes.count()
            rows = notes[offset:offset + page_size]
            return Response({
                "results": NoteSummarySerializer(
                    rows, many=True, context={"request": request},
                ).data,
                "total": total,
                "offset": offset,
                "limit": page_size,
                "has_more": offset + page_size < total,
            })
        return Response(
            NoteSummarySerializer(notes, many=True, context={"request": request}).data
        )


class NoteListCreateApiView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [permissions.AllowAny()]
        return [permissions.IsAuthenticated()]

    def get(self, request):
        creator = ensure_creator(request.user) if request.user.is_authenticated else None
        course_id = request.query_params.get("course_id")
        query = request.query_params.get("q", "").strip()
        # scope filter, applied before pagination:
        #   personal (default) — own notes, both private and public.
        #   private            — own notes, private only.
        #   public             — own notes, public only.
        #   all                — own notes plus public notes from any other
        #                        user; widens the result set for cross-user
        #                        discovery.
        # Anonymous users always see public notes only, regardless of the
        # requested scope.
        scope = request.query_params.get("scope", "personal").strip().lower()
        # sort: newest (default) | oldest | popular (most study sessions).
        # window: recency filter on date_created in days — 3 / 7 / 30 / 365,
        #   or "all" (default) for no time bound. "Most popular in 1 week"
        #   = sort=popular + window=7.
        sort = request.query_params.get("sort", "newest").strip().lower()
        window = request.query_params.get("window", "all").strip().lower()
        limit = request.query_params.get("limit")
        offset = int(request.query_params.get("offset", "0") or 0)
        notes = Note.objects.filter(
            deleted_at__isnull=True,
        ).select_related("course_id", "creator_id__user_id")
        window_days = {"3": 3, "7": 7, "30": 30, "365": 365}.get(window)
        if window_days is not None:
            notes = notes.filter(
                date_created__gte=timezone.now() - timedelta(days=window_days)
            )
        if creator is None:
            notes = notes.filter(is_public=True)
        elif scope == "all":
            notes = notes.filter(
                Q(creator_id=creator) | Q(is_public=True),
            )
        elif scope == "private":
            notes = notes.filter(creator_id=creator, is_public=False)
        elif scope == "public":
            notes = notes.filter(creator_id=creator, is_public=True)
        else:
            # personal — default fallthrough; also handles unknown scope
            # values defensively (treat anything we don't recognize as
            # personal so a stale frontend doesn't break with a 400).
            notes = notes.filter(creator_id=creator)
        if course_id:
            notes = notes.filter(course_id_id=course_id)
        if query:
            ranked_notes = []
            for note in notes:
                score = note_search_score(note, query)
                if score is None:
                    continue
                ranked_notes.append((score[0], timezone.localtime(note.last_edit), note))
            ranked_notes.sort(key=lambda item: (-item[0], -item[1].timestamp(), item[2].title.lower()))
            notes = [item[2] for item in ranked_notes]
        elif sort == "oldest":
            notes = list(notes.order_by("date_created", "id"))
        elif sort == "popular":
            notes = list(
                notes.annotate(_session_count=Count("activity_sessions"))
                .order_by("-_session_count", "-date_created", "id")
            )
        else:
            # newest (default) — also the fallthrough for unknown sort values.
            notes = list(notes.order_by("-date_created", "-id"))
        if limit is not None:
            page_size = max(1, min(int(limit), 100))
            total = len(notes)
            rows = notes[offset: offset + page_size]
            return Response(
                {
                    "results": NoteSummarySerializer(
                        rows,
                        many=True,
                        context={"request": request},
                    ).data,
                    "total": total,
                    "offset": offset,
                    "limit": page_size,
                    "has_more": offset + page_size < total,
                }
            )
        return Response(NoteSummarySerializer(notes, many=True, context={"request": request}).data)

    def post(self, request):
        serializer = NoteWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        creator = ensure_creator(request.user)
        course = None
        if serializer.validated_data.get("course_id"):
            course = get_object_or_404(Course, pk=serializer.validated_data["course_id"])
        client_draft_id = serializer.validated_data.get("client_draft_id") or None
        existing = None
        if client_draft_id:
            existing = Note.objects.filter(
                creator_id=creator,
                client_draft_id=client_draft_id,
            ).first()
        if existing is not None:
            note = existing
            note.deleted_at = None
            note.course_id = course
            note.title = serializer.validated_data["title"]
            note.description = serializer.validated_data.get("description") or ""
            note.is_public = serializer.validated_data.get("is_public", False)
            note.content = serializer.validated_data.get("content") or serializer.validated_data.get("markdown") or ""
            note.metadata_json = serializer.validated_data.get("metadata_json") or ""
            if "custom_meta" in serializer.validated_data:
                note.custom_meta = serializer.validated_data.get("custom_meta") or ""
            note.editor_mode = serializer.validated_data.get("editor_mode") or creator.editor_mode
            note.save()
            RecycleBinEntry.objects.filter(creator_id=creator, note_id=note).delete()
        else:
            source_note = None
            source_uuid = serializer.validated_data.get("source_note_uuid")
            if source_uuid:
                source_note = Note.objects.filter(uuid=source_uuid, deleted_at__isnull=True).first()
            note = Note.objects.create(
                creator_id=creator,
                course_id=course,
                sharing_id=generate_unique_id(Note, "sharing_id"),
                title=serializer.validated_data["title"],
                description=serializer.validated_data.get("description") or "",
                is_public=serializer.validated_data.get("is_public", False),
                content=serializer.validated_data.get("content") or serializer.validated_data.get("markdown") or "",
                metadata_json=serializer.validated_data.get("metadata_json") or "",
                custom_meta=serializer.validated_data.get("custom_meta") or "",
                client_draft_id=client_draft_id,
                editor_mode=serializer.validated_data.get("editor_mode") or creator.editor_mode,
                note_type=serializer.validated_data.get("note_type", "N"),
                source_note=source_note,
            )
        block_rows = serializer.validated_data.get("blocks")
        if block_rows:
            replace_note_blocks_from_payload(note, creator, block_rows)
        elif existing is not None:
            replace_note_blocks(
                note=note,
                creator=creator,
                markdown=note.content or note.description or note.title,
            )
        else:
            create_blocks_from_markdown(
                note=note,
                creator=creator,
                markdown=note.content or note.description or note.title,
            )
        record_note_activity(
            note,
            note_word_count(note),
            HeatmapActivityTypeChoices.EDITED if existing is not None else HeatmapActivityTypeChoices.CREATED,
        )
        # Give the note a stable, course-unique URL name (0.1.177) so it
        # can be linked and resolved from sibling notes' markdown.
        if not note.name and note.course_id_id:
            from .services import ensure_note_name
            ensure_note_name(note)
            if note.name:
                note.save(update_fields=["name"])
        arm_course_sync(note)
        response_status = status.HTTP_200_OK if existing is not None else status.HTTP_201_CREATED
        logger.info(
            "Note %s: Backend.Notes.Notes/create_or_upsert \u2014 "
            "creator=%s note_id=%s client_draft_id=%s course_id=%s "
            "editor_mode=%s.",
            "upserted" if existing is not None else "created",
            creator.user_id.username,
            note.id,
            client_draft_id or "<none>",
            note.course_id_id,
            note.editor_mode,
        )
        return Response(
            NoteDetailSerializer(note, context={"request": request}).data,
            status=response_status,
        )


class NoteDetailApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, note_id):
        note = require_note_access(request, note_id)
        data = NoteDetailSerializer(note, context={"request": request}).data
        data["can_edit"] = (
            request.user.is_authenticated
            and note.creator_id.user_id_id == request.user.id
        )
        return Response(data)

    def patch(self, request, note_id):
        if not request.user.is_authenticated:
            return Response(
                {"detail": (
                    "Cannot update note: "
                    "Backend.Notes.Notes/update \u2014 "
                    "request has no authenticated user."
                )},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            logger.warning(
                "Cannot update note: "
                "Backend.Notes.Notes/update \u2014 "
                "403 on note_id=%s (requesting_user=%s, owner_user_id=%s).",
                note_id,
                request.user.username,
                note.creator_id.user_id_id,
            )
            return Response(
                {"detail": (
                    "Cannot update note: "
                    "Backend.Notes.Notes/update \u2014 "
                    "note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        serializer = NoteWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field in [
            "title",
            "description",
            "metadata_json",
            "custom_meta",
            "editor_mode",
            "is_public",
        ]:
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
        arm_course_sync(note)
        logger.info(
            "Note updated: Backend.Notes.Notes/update \u2014 "
            "creator=%s note_id=%s fields=%s.",
            request.user.username,
            note.id,
            sorted(serializer.validated_data.keys()),
        )
        return Response(NoteDetailSerializer(note, context={"request": request}).data)

    def delete(self, request, note_id):
        if not request.user.is_authenticated:
            return Response(
                {"detail": (
                    "Cannot delete note: "
                    "Backend.Notes.Notes/delete \u2014 "
                    "request has no authenticated user."
                )},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot delete note: "
                    "Backend.Notes.Notes/delete \u2014 "
                    "note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        logger.info(
            "Note soft-deleted: Backend.Notes.Notes/delete \u2014 "
            "creator=%s note_id=%s (moved to recycle bin).",
            request.user.username,
            note.id,
        )
        # When a source note is deleted, its comments become private but are NOT deleted.
        note.comments.filter(deleted_at__isnull=True).update(is_public=False)
        note.deleted_at = timezone.now()
        note.is_public = False
        note.save(update_fields=["deleted_at", "is_public", "last_edit"])
        RecycleBinEntry.objects.update_or_create(
            creator_id=note.creator_id,
            note_id=note,
            defaults={
                "item_type": "note",
                "deleted_at": note.deleted_at,
                "metadata_json": json.dumps(
                    {
                        "title": note.title,
                        "description": note.description or "",
                        "course_id": note.course_id_id,
                    },
                    sort_keys=True,
                ),
            },
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class NoteByUuidApiView(APIView):
    """Look up a note by its public UUID. Supports GET (read), PATCH (edit),
    and DELETE with the same access policy as NoteDetailApiView."""
    permission_classes = [permissions.AllowAny]

    def _get_note(self, request, note_uuid):
        note = get_object_or_404(
            Note.objects.select_related("course_id", "creator_id__user_id")
            .filter(deleted_at__isnull=True),
            uuid=note_uuid,
        )
        if not can_access_note(request, note):
            raise serializers.ValidationError(
                "Note access denied: "
                "Backend.Notes.Notes/access_check_by_uuid \u2014 "
                "note is private and the requester is not its owner."
            )
        return note

    def get(self, request, note_uuid):
        note = self._get_note(request, note_uuid)
        data = NoteDetailSerializer(note, context={"request": request}).data
        data["can_edit"] = (
            request.user.is_authenticated
            and note.creator_id.user_id_id == request.user.id
        )
        return Response(data)

    def patch(self, request, note_uuid):
        if not request.user.is_authenticated:
            return Response(
                {"detail": (
                    "Cannot update note: "
                    "Backend.Notes.Notes/update_by_uuid \u2014 "
                    "request has no authenticated user."
                )},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        note = self._get_note(request, note_uuid)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot update note: "
                    "Backend.Notes.Notes/update_by_uuid \u2014 "
                    "note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        serializer = NoteWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field in [
            "title",
            "description",
            "metadata_json",
            "custom_meta",
            "editor_mode",
            "is_public",
        ]:
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
            replacement_markdown = serializer.validated_data.get("content") or serializer.validated_data.get("markdown") or note.content
            note.content = replacement_markdown
            note.save(update_fields=["content", "last_edit"])
            replace_note_blocks(note, note.creator_id, replacement_markdown)
            record_note_activity(note, note_word_count(note), HeatmapActivityTypeChoices.EDITED)
        arm_course_sync(note)
        data = NoteDetailSerializer(note, context={"request": request}).data
        data["can_edit"] = True
        return Response(data)

    def delete(self, request, note_uuid):
        if not request.user.is_authenticated:
            return Response(
                {"detail": (
                    "Cannot delete note: "
                    "Backend.Notes.Notes/delete_by_uuid \u2014 "
                    "request has no authenticated user."
                )},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        note = self._get_note(request, note_uuid)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot delete note: "
                    "Backend.Notes.Notes/delete_by_uuid \u2014 "
                    "note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        note.comments.filter(deleted_at__isnull=True).update(is_public=False)
        note.deleted_at = timezone.now()
        note.is_public = False
        note.save(update_fields=["deleted_at", "is_public", "last_edit"])
        RecycleBinEntry.objects.update_or_create(
            creator_id=note.creator_id,
            note_id=note,
            defaults={
                "item_type": "note",
                "deleted_at": note.deleted_at,
                "metadata_json": json.dumps(
                    {
                        "title": note.title,
                        "description": note.description or "",
                        "course_id": note.course_id_id,
                    },
                    sort_keys=True,
                ),
            },
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class NoteBlocksApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, note_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot add block: "
                    "Backend.Notes.Blocks/add \u2014 "
                    "parent note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
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
        return Response(
            NoteBlockSerializer(block, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )


class SingleBlockApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, block_id):
        block = get_object_or_404(NoteBlock.objects.select_related("note_id", "creator_id__user_id"), pk=block_id)
        if block.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot update block: "
                    "Backend.Notes.Blocks/update \u2014 "
                    "block is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
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
        return Response(NoteBlockSerializer(block, context={"request": request}).data)

    def delete(self, request, block_id):
        block = get_object_or_404(NoteBlock.objects.select_related("creator_id__user_id"), pk=block_id)
        if block.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot delete block: "
                    "Backend.Notes.Blocks/delete \u2014 "
                    "block is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
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
            return Response(
                {"detail": (
                    "Cannot reorder blocks: "
                    "Backend.Notes.Blocks/reorder \u2014 "
                    "parent note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        serializer = ReorderSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        handles = {
            handle.noteblock_id_id: handle
            for handle in NoteIndex.objects.filter(note_id=note)
        }
        ordered_ids = serializer.validated_data["ordered_block_ids"]
        if set(handles.keys()) != set(ordered_ids):
            raise serializers.ValidationError(
                "Reorder list rejected: "
                "Backend.Notes.Blocks/reorder \u2014 "
                "ordered_block_ids must contain every existing block id "
                "exactly once (no missing or duplicate ids)."
            )
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
            return Response(
                {"detail": (
                    "Cannot view note history: "
                    "Backend.Notes.Notes/history \u2014 "
                    "note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        return Response(NoteVersionSerializer(note.versions.all()[:12], many=True).data)


class NoteSnapshotApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, note_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot snapshot note: "
                    "Backend.Notes.Notes/snapshot \u2014 "
                    "note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        version = snapshot_note_version(note, reason=request.data.get("reason", "manual"))
        return Response(NoteVersionSerializer(version).data, status=status.HTTP_201_CREATED)


class NoteRestoreApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, note_id, version_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot restore note version: "
                    "Backend.Notes.Notes/restore \u2014 "
                    "note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        version = get_object_or_404(NoteVersion, pk=version_id, note_id=note)
        snapshot_note_version(note, reason="before_restore")
        restore_note_version(note, version)
        replace_note_blocks(note, note.creator_id, note.content or note_markdown(note))
        return Response(NoteDetailSerializer(note, context={"request": request}).data)


class DeletedNoteListApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        creator = ensure_creator(request.user)
        entries = RecycleBinEntry.objects.filter(
            creator_id=creator,
            note_id__deleted_at__isnull=False,
        ).select_related("note_id__course_id", "note_id__creator_id__user_id")
        return Response([deleted_note_summary_payload(entry, request) for entry in entries])


class DeletedNoteRestoreApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, note_id):
        creator = ensure_creator(request.user)
        note = get_object_or_404(Note, pk=note_id, creator_id=creator, deleted_at__isnull=False)
        note.deleted_at = None
        note.save(update_fields=["deleted_at", "last_edit"])
        RecycleBinEntry.objects.filter(creator_id=creator, note_id=note).delete()
        return Response(NoteDetailSerializer(note, context={"request": request}).data)


class DeletedNoteEmptyApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request):
        creator = ensure_creator(request.user)
        deleted_entries = RecycleBinEntry.objects.filter(
            creator_id=creator,
            note_id__deleted_at__isnull=False,
        )
        deleted_note_ids = list(deleted_entries.values_list("note_id_id", flat=True))
        deleted_count = len(deleted_note_ids)
        deleted_entries.delete()
        deleted_notes = Note.objects.filter(id__in=deleted_note_ids)
        deleted_notes.delete()
        return Response({
            "count": deleted_count,
            "deleted_count": deleted_count,
        })


class TemplateCourseRestoreApiView(APIView):
    permission_classes = [permissions.IsAdminUser]

    def post(self, request):
        buffer = io.StringIO()
        # This endpoint is the explicit "restore the demo/template courses"
        # admin action, so it opts into the sample catalog that the default
        # bootstrap now skips.
        call_command("bootstrap_platform", with_sample_content=True, stdout=buffer)
        creator = ensure_creator(request.user)
        subscription_map = active_subscription_map(creator)
        courses = list(
            Course.objects.select_related("creator_id__user_id")
            .prefetch_related("media_items")
            .all()
        )
        courses.sort(key=lambda course: course_sort_key(course, subscription_map))
        return Response(
            {
                "message": "Template courses restored.",
                "log": buffer.getvalue(),
                "courses": CourseSerializer(
                    courses,
                    many=True,
                    context={"request": request, "subscription_map": subscription_map},
                ).data,
            }
        )


class CourseSubscribeApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, course_id):
        creator = ensure_creator(request.user)
        course = get_object_or_404(Course, pk=course_id)
        subscription, created = CourseSubscription.objects.get_or_create(
            creator_id=creator,
            course_id=course,
            defaults={"is_active": True, "is_private": False, "subscribed_at": timezone.now()},
        )
        if not created:
            subscription.is_active = True
            subscription.is_private = False
            subscription.subscribed_at = timezone.now()
            subscription.save(update_fields=["is_active", "is_private", "subscribed_at", "last_edit"])
        append_course_operation(creator, course, CourseOperationTypeChoices.SUBSCRIBE)
        subscription_map = active_subscription_map(creator)
        return Response(
            CourseSerializer(
                course,
                context={"request": request, "subscription_map": subscription_map},
            ).data
        )

    def delete(self, request, course_id):
        creator = ensure_creator(request.user)
        course = get_object_or_404(Course, pk=course_id)
        subscription = get_object_or_404(
            CourseSubscription,
            creator_id=creator,
            course_id=course,
            is_active=True,
        )
        subscription.is_active = False
        subscription.save(update_fields=["is_active", "last_edit"])
        append_course_operation(creator, course, CourseOperationTypeChoices.UNSUBSCRIBE)
        subscription_map = active_subscription_map(creator)
        return Response(
            CourseSerializer(
                course,
                context={"request": request, "subscription_map": subscription_map},
            ).data
        )


class CourseSubscribePrivateApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, course_id):
        creator = ensure_creator(request.user)
        course = get_object_or_404(Course, pk=course_id)
        subscription, created = CourseSubscription.objects.get_or_create(
            creator_id=creator,
            course_id=course,
            defaults={"is_active": True, "is_private": True, "subscribed_at": timezone.now()},
        )
        if not created:
            subscription.is_active = True
            subscription.is_private = True
            subscription.subscribed_at = timezone.now()
            subscription.save(update_fields=["is_active", "is_private", "subscribed_at", "last_edit"])
        append_course_operation(creator, course, CourseOperationTypeChoices.SUBSCRIBE)
        subscription_map = active_subscription_map(creator)
        return Response(
            CourseSerializer(
                course,
                context={"request": request, "subscription_map": subscription_map},
            ).data
        )


class CourseOpenApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, course_id):
        creator = ensure_creator(request.user)
        course = get_object_or_404(Course, pk=course_id)
        subscription = get_object_or_404(
            CourseSubscription,
            creator_id=creator,
            course_id=course,
            is_active=True,
        )
        subscription.last_opened_at = timezone.now()
        subscription.save(update_fields=["last_opened_at", "last_edit"])
        append_course_operation(creator, course, CourseOperationTypeChoices.OPEN)
        subscription_map = active_subscription_map(creator)
        return Response(
            CourseSerializer(
                course,
                context={"request": request, "subscription_map": subscription_map},
            ).data
        )


class ActivityApiView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        if not request.user.is_authenticated:
            return Response([])
        notes = Note.objects.filter(
            creator_id__user_id=request.user,
            deleted_at__isnull=True,
        ).select_related("course_id", "creator_id__user_id").order_by("-last_edit")
        return Response(NoteSummarySerializer(notes[:10], many=True, context={"request": request}).data)


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
        day_count = DEFAULT_CALENDAR_RANGE_DAYS
        raw_days = request.query_params.get("days")
        if raw_days:
            try:
                day_count = int(raw_days)
            except ValueError:
                day_count = DEFAULT_CALENDAR_RANGE_DAYS
        return Response(
            calendar_week_payload(
                creator, start_date=parsed_start, day_count=day_count
            )
        )


class HeatmapApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        creator = ensure_creator(request.user)
        return Response(build_heatmap_payload(creator))


class PlannerEventListCreateApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        creator = ensure_creator(request.user)
        events = PlannerEvent.objects.filter(creator_id=creator)
        # Opt-in extras so the CLI MCP server can mirror the in-backend
        # list_events tool; defaults preserve the original contract
        # (incomplete only, no truncation).
        if request.query_params.get("include_completed") not in ("1", "true"):
            events = events.filter(is_completed=False)
        events = events.order_by("event_date", "title")
        raw_limit = request.query_params.get("limit")
        if raw_limit is not None:
            try:
                events = events[: max(1, min(int(raw_limit), 200))]
            except (TypeError, ValueError):
                pass
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
            is_completed=serializer.validated_data.get("is_completed", False),
            completed_at=serializer.validated_data.get("completed_at"),
            recurrence_freq=serializer.validated_data.get("recurrence_freq", "N"),
            recurrence_interval=serializer.validated_data.get("recurrence_interval", 1),
            recurrence_end_date=serializer.validated_data.get("recurrence_end_date"),
            recurrence_count=serializer.validated_data.get("recurrence_count"),
        )
        normalize_planner_event_window(event)
        if event.is_completed and event.completed_at is None:
            event.completed_at = timezone.now()
            event.save(update_fields=["completed_at", "last_edit"])
        return Response(planner_event_payload(event), status=status.HTTP_201_CREATED)


class PlannerEventDetailApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, event_id):
        creator = ensure_creator(request.user)
        event = get_object_or_404(PlannerEvent, pk=event_id, creator_id=creator)
        serializer = PlannerEventWriteSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field in [
            "title",
            "event_date",
            "starts_at",
            "ends_at",
            "difficulty_weight",
            "description",
            "is_completed",
            "completed_at",
            "recurrence_freq",
            "recurrence_interval",
            "recurrence_end_date",
            "recurrence_count",
        ]:
            if field in serializer.validated_data:
                setattr(event, field, serializer.validated_data[field])
        if "course_id" in serializer.validated_data:
            course_id = serializer.validated_data["course_id"]
            event.course_id = get_object_or_404(Course, pk=course_id) if course_id is not None else None
        if "is_completed" in serializer.validated_data and serializer.validated_data["is_completed"] is True and event.completed_at is None:
            event.completed_at = timezone.now()
        if "is_completed" in serializer.validated_data and serializer.validated_data["is_completed"] is False:
            event.completed_at = None
        event.save()
        normalize_planner_event_window(event)
        return Response(planner_event_payload(event))


class NoteSessionListCreateApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        creator = ensure_creator(request.user)
        sessions = NoteActivitySession.objects.filter(creator_id=creator)
        note_id = request.query_params.get("note_id")
        if note_id:
            sessions = sessions.filter(note_id_id=note_id)
        sessions = sessions.order_by("-started_at", "-id")
        try:
            limit = min(int(request.query_params.get("limit", 50)), 200)
        except (TypeError, ValueError):
            limit = 50
        return Response(
            [note_session_payload(session) for session in sessions[:limit]]
        )

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
        # Normalize Google Calendar share URLs to their canonical `.ics` form
        # before persisting. This turns the HTML share link that users most
        # commonly paste into a URL the feed reader can actually consume.
        source_url = serializer.validated_data.get("source_url") or ""
        if source_url:
            source_url = normalize_calendar_url(source_url)
        feed = CalendarFeed.objects.create(
            creator_id=creator,
            course_id=course,
            title=serializer.validated_data["title"],
            source_kind=serializer.validated_data.get("source_kind", "I"),
            source_url=source_url,
            raw_ical=serializer.validated_data.get("raw_ical") or "",
            is_enabled=serializer.validated_data.get("is_enabled", True),
        )
        # Parse the feed once now so the client can show an import-result
        # modal (success + a short list of events, or a readable error)
        # instead of silently rendering zero events.
        payload = CalendarFeedSerializer(feed).data
        payload["import_summary"] = summarize_calendar_feed(feed)
        return Response(payload, status=status.HTTP_201_CREATED)


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


# ---------------------------------------------------------------------------
# Note Attachments
# ---------------------------------------------------------------------------

_MAX_ATTACHMENT_SIZE = 20 * 1024 * 1024  # 20 MB


def attachment_payload(attachment: NoteAttachment, request):
    return {
        "id": attachment.id,
        "note_id": attachment.note_id_id,
        "original_filename": attachment.original_filename,
        "file_size": attachment.file_size,
        "content_type": attachment.content_type,
        "url": absolute_media_url(request, attachment.file.url if attachment.file else ""),
        "date_created": attachment.date_created.isoformat() if attachment.date_created else None,
    }


class NoteAttachmentApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, note_id):
        note = require_note_access(request, note_id)
        attachments = NoteAttachment.objects.filter(note_id=note)
        return Response([attachment_payload(a, request) for a in attachments])

    def post(self, request, note_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": "Only the owner can upload attachments."},
                status=status.HTTP_403_FORBIDDEN,
            )
        uploaded = request.FILES.get("file")
        if not uploaded:
            return Response(
                {"detail": "No file provided."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if uploaded.size > _MAX_ATTACHMENT_SIZE:
            return Response(
                {"detail": f"File exceeds maximum size of {_MAX_ATTACHMENT_SIZE // (1024 * 1024)} MB."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        attachment = NoteAttachment.objects.create(
            note_id=note,
            file=uploaded,
            original_filename=uploaded.name or "untitled",
            file_size=uploaded.size,
            content_type=uploaded.content_type or "",
        )
        return Response(
            attachment_payload(attachment, request),
            status=status.HTTP_201_CREATED,
        )


class NoteAttachmentDetailApiView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request, note_id, attachment_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": "Only the owner can delete attachments."},
                status=status.HTTP_403_FORBIDDEN,
            )
        attachment = get_object_or_404(NoteAttachment, pk=attachment_id, note_id=note)
        attachment.file.delete(save=False)
        attachment.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


def _get_note_by_uuid(request, note_uuid):
    """Look up a non-deleted note by UUID with access check.
    Shared helper for UUID-keyed endpoints."""
    note = get_object_or_404(
        Note.objects.select_related("course_id", "creator_id__user_id")
        .filter(deleted_at__isnull=True),
        uuid=note_uuid,
    )
    if not can_access_note(request, note):
        raise serializers.ValidationError(
            "Note access denied: "
            "Backend.Notes.Notes/access_check_by_uuid — "
            "note is private and the requester is not its owner."
        )
    return note


class NoteAttachmentByUuidApiView(APIView):
    """List / create attachments for a note looked up by UUID.
    Mirrors NoteAttachmentApiView but accepts note_uuid (UUID)
    in the URL instead of note_id (integer PK)."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, note_uuid):
        note = _get_note_by_uuid(request, note_uuid)
        attachments = NoteAttachment.objects.filter(note_id=note)
        return Response([attachment_payload(a, request) for a in attachments])

    def post(self, request, note_uuid):
        note = _get_note_by_uuid(request, note_uuid)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": "Only the owner can upload attachments."},
                status=status.HTTP_403_FORBIDDEN,
            )
        uploaded = request.FILES.get("file")
        if not uploaded:
            return Response(
                {"detail": "No file provided."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if uploaded.size > _MAX_ATTACHMENT_SIZE:
            return Response(
                {"detail": f"File exceeds maximum size of {_MAX_ATTACHMENT_SIZE // (1024 * 1024)} MB."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        attachment = NoteAttachment.objects.create(
            note_id=note,
            file=uploaded,
            original_filename=uploaded.name or "untitled",
            file_size=uploaded.size,
            content_type=uploaded.content_type or "",
        )
        return Response(
            attachment_payload(attachment, request),
            status=status.HTTP_201_CREATED,
        )


class NoteAttachmentByUuidDetailApiView(APIView):
    """Delete an attachment by note UUID + attachment ID.
    Mirrors NoteAttachmentDetailApiView but looks up the note
    by UUID in the URL."""

    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request, note_uuid, attachment_id):
        note = _get_note_by_uuid(request, note_uuid)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": "Only the owner can delete attachments."},
                status=status.HTTP_403_FORBIDDEN,
            )
        attachment = get_object_or_404(NoteAttachment, pk=attachment_id, note_id=note)
        attachment.file.delete(save=False)
        attachment.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


_MAX_COVER_IMAGE_SIZE = 5 * 1024 * 1024  # 5 MB — covers shouldn't be huge


class NoteCoverImageApiView(APIView):
    """Upload (POST) / clear (DELETE) the per-note cover image. Same
    multipart pattern as NoteAttachmentApiView; the field name on POST
    is `cover`. Returns the updated NoteSummarySerializer payload so the
    frontend can replace its cached note row in one round-trip."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, note_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot set cover image: "
                    "Backend.Notes.Notes/cover_upload — "
                    "note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        uploaded = request.FILES.get("cover")
        if not uploaded:
            return Response(
                {"detail": (
                    "Cannot set cover image: "
                    "Backend.Notes.Notes/cover_upload — "
                    "no `cover` file part in the request."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if uploaded.size > _MAX_COVER_IMAGE_SIZE:
            return Response(
                {"detail": (
                    "Cannot set cover image: "
                    "Backend.Notes.Notes/cover_upload — "
                    f"file exceeds maximum size of "
                    f"{_MAX_COVER_IMAGE_SIZE // (1024 * 1024)} MB."
                )},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # Delete the old file before saving the new one so we don't
        # accumulate orphans in object storage.
        if note.cover_image:
            note.cover_image.delete(save=False)
        note.cover_image = uploaded
        note.save(update_fields=["cover_image", "last_edit"])
        return Response(
            NoteSummarySerializer(note, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )

    def delete(self, request, note_id):
        note = require_note_access(request, note_id)
        if note.creator_id.user_id_id != request.user.id:
            return Response(
                {"detail": (
                    "Cannot clear cover image: "
                    "Backend.Notes.Notes/cover_delete — "
                    "note is owned by a different user."
                )},
                status=status.HTTP_403_FORBIDDEN,
            )
        if note.cover_image:
            note.cover_image.delete(save=False)
            note.cover_image = None
            note.save(update_fields=["cover_image", "last_edit"])
        return Response(
            NoteSummarySerializer(note, context={"request": request}).data,
            status=status.HTTP_200_OK,
        )
