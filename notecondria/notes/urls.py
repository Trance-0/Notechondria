"""
Mapping the url requrest

This file maps the url requrest from member app and share it with notecondria.url
"""

from django.urls import path
from . import views

urlpatterns = [
    path('', views.notes, name='notes'),
    path('snippets/new',views.notes,name='add_snippets'),
    path('notes/new',views.notes,name='add_notes')
]