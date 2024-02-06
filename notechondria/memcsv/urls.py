"""
Mapping the url requrest

This file maps the url requrest from member app and share it with notechondria.url
"""

from django.urls import path
from . import views

urlpatterns = [
    # path('/create'),
    path('/list', views.memlist, name='list'),
    path('/test/<int:rec_pk>',views.memtest,name='test')
]