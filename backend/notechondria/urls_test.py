from django.urls import include, path
from . import views

urlpatterns = [
    path('', views.home, name='home'),
    path('about/', views.about, name='about'),
    path('dashboard/', views.dashboard, name='dashboard'),
    path('search/', views.about, name='search'),
    path('notes/', include(('notes.urls', 'notes'), namespace='notes')),
    path('gptutils/', include(('gptutils.urls', 'recipes'), namespace='gptutils')),
    path('creators/', include(('creators.urls', 'creators'), namespace='creators')),
]
