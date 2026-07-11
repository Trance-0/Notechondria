from django.urls import path

from notechondria.api_views import handshake as handshake_view
from notechondria.api_views import ping as ping_view

from creators.api import (
    CasdoorBindApiView,
    CasdoorConfigApiView,
    CasdoorExchangeApiView,
    CasdoorLinkBindApiView,
    CasdoorLinkCreateApiView,
    CasdoorUnlinkApiView,
    GithubSyncCallbackApiView,
    GithubSyncPushApiView,
    GithubSyncReposApiView,
    GithubSyncStatusApiView,
    LoginApiView,
    RotateApiKeyApiView,
    SettingsApiView,
)
from notes.api import (
    ActivityApiView,
    ActivityWeekApiView,
    CalendarFeedDetailApiView,
    CalendarFeedListCreateApiView,
    CourseDetailApiView,
    CourseGitBindingApiView,
    CourseGitImportApiView,
    CourseGitSyncApiView,
    CourseListApiView,
    CourseNotesApiView,
    CourseReorderApiView,
    CourseOpenApiView,
    CourseSubscribeApiView,
    CourseSubscribePrivateApiView,
    DeletedNoteEmptyApiView,
    DeletedNoteListApiView,
    DeletedNoteRestoreApiView,
    FrontPageApiView,
    HeatmapApiView,
    NoteAttachmentApiView,
    NoteAttachmentByUuidApiView,
    NoteAttachmentByUuidDetailApiView,
    NoteAttachmentDetailApiView,
    NoteBlocksApiView,
    NoteCoverImageApiView,
    NoteByUuidApiView,
    NoteDetailApiView,
    NoteHistoryApiView,
    NoteListCreateApiView,
    NoteRestoreApiView,
    NoteSessionDetailApiView,
    NoteSessionListCreateApiView,
    NoteSnapshotApiView,
    PlannerEventDetailApiView,
    PlannerEventListCreateApiView,
    ReorderBlocksApiView,
    SingleBlockApiView,
    TemplateCourseRestoreApiView,
)


urlpatterns = [
    path("health/", FrontPageApiView.health, name="health"),
    path("handshake/", handshake_view, name="handshake"),
    path("ping/", ping_view, name="ping"),
    path("auth/rotate-api-key/", RotateApiKeyApiView.as_view(), name="rotate-api-key"),
    # Username/password fallback so existing users can still sign in
    # when Casdoor is down or misconfigured. Restored in 0.1.111.
    # Casdoor SSO remains the primary surface; this view only mints a
    # DRF stock authtoken_token row for an already-existing user. No
    # register / password reset / email verification — those live on
    # `auth.trance-0.com`.
    path("auth/login/", LoginApiView.as_view(), name="auth-login"),
    # Casdoor SSO routes (since 0.1.96). Signup, password reset, and
    # session lifecycle live on `auth.trance-0.com`. See
    # docs/integrations/casdoor-migration.md.
    path("auth/casdoor/config/", CasdoorConfigApiView.as_view(), name="casdoor-config"),
    path("auth/casdoor/exchange/", CasdoorExchangeApiView.as_view(), name="casdoor-exchange"),
    # Gitea-style account-link choice (since 0.1.118): when the
    # exchange returns a `link_challenge` instead of an auth_payload,
    # the SPA prompts the user to either bind to an existing legacy
    # account (proves ownership via username + password) or create a
    # fresh account with a user-chosen password. Both endpoints
    # accept the nonce returned by the exchange and return the
    # standard auth_payload on success.
    path("auth/casdoor/link/bind/", CasdoorLinkBindApiView.as_view(), name="casdoor-link-bind"),
    path("auth/casdoor/link/create/", CasdoorLinkCreateApiView.as_view(), name="casdoor-link-create"),
    path("auth/casdoor/bind/", CasdoorBindApiView.as_view(), name="casdoor-bind"),
    path("auth/casdoor/unlink/", CasdoorUnlinkApiView.as_view(), name="casdoor-unlink"),
    path("front-page/", FrontPageApiView.as_view(), name="front-page"),
    path("courses/", CourseListApiView.as_view(), name="course-list"),
    path("courses/reorder/", CourseReorderApiView.as_view(), name="course-reorder"),
    path("courses/<int:course_id>/", CourseDetailApiView.as_view(), name="course-detail"),
    path("courses/<int:course_id>/git/", CourseGitBindingApiView.as_view(), name="course-git-binding"),
    path("courses/<int:course_id>/git/import/", CourseGitImportApiView.as_view(), name="course-git-import"),
    path("courses/<int:course_id>/git/sync/", CourseGitSyncApiView.as_view(), name="course-git-sync"),
    path("courses/<int:course_id>/notes/", CourseNotesApiView.as_view(), name="course-notes"),
    path("courses/<int:course_id>/subscribe/", CourseSubscribeApiView.as_view(), name="course-subscribe"),
    path("courses/<int:course_id>/subscribe-private/", CourseSubscribePrivateApiView.as_view(), name="course-subscribe-private"),
    path("courses/<int:course_id>/open/", CourseOpenApiView.as_view(), name="course-open"),
    path("admin/template-courses/restore/", TemplateCourseRestoreApiView.as_view(), name="template-course-restore"),
    path("notes/", NoteListCreateApiView.as_view(), name="note-list-create"),
    path("notes/deleted/", DeletedNoteListApiView.as_view(), name="deleted-note-list"),
    path("notes/deleted/empty/", DeletedNoteEmptyApiView.as_view(), name="deleted-note-empty"),
    path("notes/uuid/<uuid:note_uuid>/", NoteByUuidApiView.as_view(), name="note-by-uuid"),
    path("notes/<int:note_id>/", NoteDetailApiView.as_view(), name="note-detail"),
    path("notes/<int:note_id>/restore/", DeletedNoteRestoreApiView.as_view(), name="deleted-note-restore"),
    path("notes/<int:note_id>/history/", NoteHistoryApiView.as_view(), name="note-history"),
    path("notes/<int:note_id>/snapshot/", NoteSnapshotApiView.as_view(), name="note-snapshot"),
    path("notes/<int:note_id>/restore/<int:version_id>/", NoteRestoreApiView.as_view(), name="note-restore"),
    path("note-sessions/", NoteSessionListCreateApiView.as_view(), name="note-session-list-create"),
    path("note-sessions/<int:session_id>/", NoteSessionDetailApiView.as_view(), name="note-session-detail"),
    path("notes/<int:note_id>/attachments/", NoteAttachmentApiView.as_view(), name="note-attachments"),
    path("notes/<int:note_id>/attachments/<int:attachment_id>/", NoteAttachmentDetailApiView.as_view(), name="note-attachment-detail"),
    path("notes/uuid/<uuid:note_uuid>/attachments/", NoteAttachmentByUuidApiView.as_view(), name="note-attachments-by-uuid"),
    path("notes/uuid/<uuid:note_uuid>/attachments/<int:attachment_id>/", NoteAttachmentByUuidDetailApiView.as_view(), name="note-attachment-detail-by-uuid"),
    path("notes/<int:note_id>/cover/", NoteCoverImageApiView.as_view(), name="note-cover"),
    path("notes/<int:note_id>/blocks/", NoteBlocksApiView.as_view(), name="note-blocks"),
    path("notes/<int:note_id>/reorder/", ReorderBlocksApiView.as_view(), name="note-reorder"),
    path("blocks/<int:block_id>/", SingleBlockApiView.as_view(), name="block-detail"),
    path("activity/", ActivityApiView.as_view(), name="activity"),
    path("activity/week/", ActivityWeekApiView.as_view(), name="activity-week"),
    path("heatmap/", HeatmapApiView.as_view(), name="heatmap"),
    path("calendar-feeds/", CalendarFeedListCreateApiView.as_view(), name="calendar-feeds"),
    path("calendar-feeds/<int:feed_id>/", CalendarFeedDetailApiView.as_view(), name="calendar-feed-detail"),
    path("planner-events/", PlannerEventListCreateApiView.as_view(), name="planner-events"),
    path("planner-events/<int:event_id>/", PlannerEventDetailApiView.as_view(), name="planner-event-detail"),
    path("settings/", SettingsApiView.as_view(), name="settings"),
    path("integrations/github/status/", GithubSyncStatusApiView.as_view(), name="github-sync-status"),
    path("integrations/github/callback/", GithubSyncCallbackApiView.as_view(), name="github-sync-callback"),
    path("integrations/github/push/", GithubSyncPushApiView.as_view(), name="github-sync-push"),
    path("integrations/github/repos/", GithubSyncReposApiView.as_view(), name="github-sync-repos"),
]
