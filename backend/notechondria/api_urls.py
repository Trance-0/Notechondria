from django.urls import path

from creators.api import (
    LoginApiView,
    LogoutApiView,
    RegisterApiView,
    ResendVerificationApiView,
    SettingsApiView,
    SessionApiView,
    VerifyEmailApiView,
)
from notes.api import (
    ActivityApiView,
    CourseDetailApiView,
    CourseListApiView,
    CourseNotesApiView,
    FrontPageApiView,
    HeatmapApiView,
    NoteBlocksApiView,
    NoteDetailApiView,
    NoteListCreateApiView,
    PlannerEventDetailApiView,
    PlannerEventListCreateApiView,
    ReorderBlocksApiView,
    SingleBlockApiView,
)


urlpatterns = [
    path("health/", FrontPageApiView.health, name="health"),
    path("auth/register/", RegisterApiView.as_view(), name="register"),
    path("auth/verify-email/", VerifyEmailApiView.as_view(), name="verify-email"),
    path("auth/resend-verification/", ResendVerificationApiView.as_view(), name="resend-verification"),
    path("auth/login/", LoginApiView.as_view(), name="login"),
    path("auth/logout/", LogoutApiView.as_view(), name="logout"),
    path("auth/session/", SessionApiView.as_view(), name="session"),
    path("front-page/", FrontPageApiView.as_view(), name="front-page"),
    path("courses/", CourseListApiView.as_view(), name="course-list"),
    path("courses/<int:course_id>/", CourseDetailApiView.as_view(), name="course-detail"),
    path("courses/<int:course_id>/notes/", CourseNotesApiView.as_view(), name="course-notes"),
    path("notes/", NoteListCreateApiView.as_view(), name="note-list-create"),
    path("notes/<int:note_id>/", NoteDetailApiView.as_view(), name="note-detail"),
    path("notes/<int:note_id>/blocks/", NoteBlocksApiView.as_view(), name="note-blocks"),
    path("notes/<int:note_id>/reorder/", ReorderBlocksApiView.as_view(), name="note-reorder"),
    path("blocks/<int:block_id>/", SingleBlockApiView.as_view(), name="block-detail"),
    path("activity/", ActivityApiView.as_view(), name="activity"),
    path("heatmap/", HeatmapApiView.as_view(), name="heatmap"),
    path("planner-events/", PlannerEventListCreateApiView.as_view(), name="planner-events"),
    path("planner-events/<int:event_id>/", PlannerEventDetailApiView.as_view(), name="planner-event-detail"),
    path("settings/", SettingsApiView.as_view(), name="settings"),
]
