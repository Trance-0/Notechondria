"""
Mapping the url requrest

This file maps the url requrest from member app and share it with notechondria.url
"""

from django.urls import path
from . import views

urlpatterns = [
    path('', views.list_notes, name='notes'),
    path('snippets/new',views.quick_notes,name='add_snippets'),
    path('notes/new',views.new_notes,name='add_notes'),
    path('notes/',views.get_note,name='add_notes'),
]