import os

from django.conf import settings
from django.contrib import admin
from django.contrib.staticfiles.views import serve as staticfiles_serve
from django.urls import include, path, re_path
from django.views.static import serve
from django.views.generic import RedirectView
from django.contrib.staticfiles.storage import staticfiles_storage
from . import api_views

handler400 = "notechondria.api_views.api_bad_request"
handler403 = "notechondria.api_views.api_permission_denied"
handler404 = "notechondria.api_views.api_page_not_found"
handler500 = "notechondria.api_views.api_server_error"

urlpatterns = [
    path('', api_views.health_check, name="health-root"),
    path('api/v1/', include(('notechondria.api_urls', 'api'), namespace='api')),
    path('admin/', admin.site.urls),
    path(
        "favicon.ico",
        RedirectView.as_view(url=staticfiles_storage.url("images/bug-fill.ico" if settings.DEBUG else "images/braces-asterisk.ico")),
    ),
]

urlpatterns += [
    re_path(
        r"^media/(?P<path>.*)$",
        serve,
        {
            "document_root": settings.MEDIA_ROOT,
        },
    ),
    re_path(
        r"^static/(?P<path>.*)$",
        staticfiles_serve,
        {
            "insecure": True,
        },
    ),
]

# config for monaco-editor js
# self-made solution for: django.request.log_response:241- 'Not Found: /min-maps/vs/base/common/worker/simpleWorker.nls.js.map'
urlpatterns += [
    re_path(
        r"^min-maps/(?P<path>.*)$",
        serve,
        {
            "document_root": os.path.join(settings.STATIC_ROOT, "monaco-editor", "min-maps"),
        },
    ),
]
