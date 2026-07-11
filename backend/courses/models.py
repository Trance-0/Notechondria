from django.db import models
from django.db.models import Q
from django.utils import timezone
from django.utils.translation import gettext_lazy as _

from creators.models import Creator


def course_media_path(instance, filename):
    return f"course_media/course_{instance.course_id_id}/{filename}"


def course_cover_path(instance, filename):
    return f"course_media/course_{instance.id or 'new'}/{filename}"


class Course(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    client_course_id = models.CharField(max_length=64, blank=True, null=True)
    slug = models.SlugField(max_length=120, unique=True)
    title = models.CharField(max_length=120, null=False)
    description = models.TextField(blank=True, null=True)
    cover_image = models.ImageField(upload_to=course_cover_path, blank=True, null=True)
    icon = models.IntegerField(blank=True, null=True, help_text="Material Icons codePoint")
    sort_order = models.IntegerField(default=0, null=False)
    # Git binding (0.1.164). A course may be bound to a GitHub repo that
    # mirrors its notes as files. The backend stays the source of
    # truth: edits land in the DB, then a lazy sync commits/pushes to
    # the repo after `git_sync_timeout_minutes` of no further edits.
    # `git_repo` is the `owner/name` full name; empty = not bound.
    git_provider = models.CharField(
        max_length=16,
        choices=(("github", "GitHub"),),
        default="github",
        null=False,
    )
    git_repo = models.CharField(max_length=255, blank=True, null=True)
    git_branch = models.CharField(max_length=255, blank=True, null=True, default="main")
    git_sync_enabled = models.BooleanField(default=False, null=False)
    # Owner-tunable lazy-commit debounce; the dev-settings UI writes it.
    git_sync_timeout_minutes = models.PositiveIntegerField(default=5, null=False)
    # Set to now() on each content edit; the sync worker fires when
    # (now - git_pending_since) >= git_sync_timeout_minutes, then clears
    # it. `git_last_synced_at` records the last successful push.
    git_pending_since = models.DateTimeField(blank=True, null=True)
    git_last_synced_at = models.DateTimeField(blank=True, null=True)
    git_last_sync_error = models.CharField(max_length=512, blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["creator_id", "client_course_id"],
                condition=Q(client_course_id__isnull=False),
                name="unique_course_client_id_per_creator",
            )
        ]
        ordering = ["sort_order", "title"]

    def __str__(self) -> str:
        return self.title


class CourseMedia(models.Model):
    course_id = models.ForeignKey(
        Course,
        related_name="media_items",
        on_delete=models.CASCADE,
        null=False,
    )
    title = models.CharField(max_length=120, null=False)
    description = models.CharField(max_length=255, blank=True, null=True)
    image = models.ImageField(upload_to=course_media_path, blank=True, null=True)
    source = models.CharField(max_length=255, blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)

    class Meta:
        ordering = ["date_created", "id"]

    def __str__(self) -> str:
        return f"{self.course_id.title}: {self.title}"


class CourseSubscription(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="course_subscriptions",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="subscriptions",
        on_delete=models.CASCADE,
        null=False,
    )
    is_active = models.BooleanField(default=True, null=False)
    is_private = models.BooleanField(default=False, null=False)
    subscribed_at = models.DateTimeField(default=timezone.now, null=False)
    last_opened_at = models.DateTimeField(blank=True, null=True)
    date_created = models.DateTimeField(auto_now_add=True, null=False)
    last_edit = models.DateTimeField(auto_now=True, null=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["creator_id", "course_id"],
                name="unique_course_subscription_per_creator",
            )
        ]
        ordering = ["-last_opened_at", "-subscribed_at", "-id"]

    def __str__(self) -> str:
        return f"{self.creator_id.user_id.username}:{self.course_id.title}"


class CourseOperationTypeChoices(models.TextChoices):
    SUBSCRIBE = "subscribe", _("Subscribe")
    UNSUBSCRIBE = "unsubscribe", _("Unsubscribe")
    OPEN = "open", _("Open")


class CourseOperationLog(models.Model):
    creator_id = models.ForeignKey(
        Creator,
        related_name="course_operation_logs",
        on_delete=models.CASCADE,
        null=False,
    )
    course_id = models.ForeignKey(
        Course,
        related_name="operation_logs",
        on_delete=models.CASCADE,
        null=False,
    )
    operation_type = models.CharField(
        max_length=16,
        choices=CourseOperationTypeChoices.choices,
        null=False,
    )
    metadata_json = models.TextField(blank=True, default="")
    occurred_at = models.DateTimeField(default=timezone.now, null=False)
    date_created = models.DateTimeField(auto_now_add=True, null=False)

    class Meta:
        ordering = ["-occurred_at", "-id"]

    def __str__(self) -> str:
        return f"{self.creator_id.user_id.username}:{self.course_id.title}:{self.operation_type}"
