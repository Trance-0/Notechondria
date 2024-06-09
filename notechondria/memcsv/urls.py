"""
Mapping the url requrest

This file maps the url requrest from member app and share it with notechondria.url
"""

from django.urls import path
from . import views

urlpatterns = [

    path('list/', views.memlist, name='list'),

    
    # Following Eason's url naming format
    path('upload_memcsv/', views.upload_memcsv, name='upload_memcsv'),
    #path('input_training/', views.input_training, name='input_training')
]