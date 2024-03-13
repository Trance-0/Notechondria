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
    path('collections/edit_block/<int:noteblock_id>',views.edit_block,name='edit_noteblock'),
    path('collections/insert_block/<int:note_id>/<int:noteblock_id>',views.insert_block,name='insert_noteblock'),
    path('collections/reorder_blocks/<int:note_id>',views.reorder_blocks,name='reorder_blocks'),
    path('collections/',views.list_notes,name='list_notes'),
    path('collections/<int:note_id>',views.view_note,name='view_note'),
    path('collections/block/<int:noteblock_id>',views.view_block,name='view_noteblock'),
]