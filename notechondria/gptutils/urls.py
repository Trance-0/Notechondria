"""
Mapping the url requrest

This file maps the url requrest from member app and share it with notechondria.url
"""

from django.urls import path
from . import views
urlpatterns = [
    path('', views.gptutils, name='main'),
    path('send/<int:pk>',views.send,name='send'),
    path('chat/<int:pk>',views.get_chat,name='get_chat'),
    path('create/',views.create_chat,name='create_chat'),
    path('one/',views.one_chat,name='one')
]