from django.urls import include, path
from . import api_views, views

urlpatterns = [
    path('', api_views.health_check, name='home'),
    path('api/v1/', include(('notechondria.api_urls', 'api'), namespace='api')),
    path('mcp/', include('mcp.urls')),
    path('about/', views.about, name='about'),
    path('dashboard/', views.dashboard, name='dashboard'),
    path('search/', views.about, name='search'),
    path('notes/', include(('notes.urls', 'notes'), namespace='notes')),
    path('gptutils/', include(('gptutils.urls', 'recipes'), namespace='gptutils')),
    path('creators/', include(('creators.urls', 'creators'), namespace='creators')),
]
