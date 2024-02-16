"""
Mapping the url request

This file maps the url request from member app and share it with notechondria.url
"""

from django.conf import settings
from django.urls import path, re_path
from django.views.static import serve
from . import views
urlpatterns = [
    path('', views.gptutils, name='main'),
    path('chat/<int:conv_pk>',views.get_chat,name='get_chat'),
    path('chat/stream/<int:conv_pk>',views.stream_chat,name='stream_chat'),
    path('chat/delete/<int:conv_pk>',views.delete_chat,name='delete_chat'),
    path('chat/edit/<int:conv_pk>',views.edit_chat,name='edit_chat'),
    path('chat/create',views.create_chat,name='create_chat'),
    path('chat/create/fast',views.fast_chat,name='fast_chat'),
    path('chat/edit_message/<int:message_pk>',views.edit_message,name='edit_message'),
    path('chat/delete_message/<int:message_pk>',views.delete_message,name='delete_message'),
]
# redirect media request to media root
if settings.DEBUG:
    urlpatterns += [
        re_path(
            r"^media/(?P<path>.*)$",
            serve,
            {
                "document_root": settings.MEDIA_ROOT,
            },
        ),
    ]