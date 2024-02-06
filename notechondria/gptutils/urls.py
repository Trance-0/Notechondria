"""
Mapping the url requrest

This file maps the url requrest from member app and share it with notechondria.url
"""

from django.urls import path
from . import views
urlpatterns = [
    path('', views.gptutils, name='main'),
    path('chat/<int:conv_pk>',views.get_chat,name='get_chat'),
    path('chat/delete/<int:conv_pk>',views.delete_chat,name='delete_chat'),
    path('chat/create',views.create_chat,name='create_chat')
]