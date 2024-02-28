"""
Mapping the url request

This file maps the url request from member app and share it with notechondria.url
"""

from django.urls import path
from . import views

urlpatterns = [
    path('', views.list_notes, name='notes'),
    path('blocks/new',views.create_block,name='create_noteblock'),
    path('notes/new',views.create_note,name='create_note'),
    path('collections/edit/<int:note_id>',views.edit_note,name='edit_note'),
    path('collections/',views.list_notes,name='list_notes'),
    path('collections/<int:note_id>',views.view_note,name='view_note'),
]