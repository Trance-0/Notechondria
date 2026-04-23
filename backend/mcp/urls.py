from django.urls import path

from .views import McpView

urlpatterns = [
    path("", McpView.as_view(), name="mcp"),
]
