"""notecondria URL Configuration

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/3.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.conf import settings
from django.contrib import admin
from django.urls import include, path,re_path
from django.views.static import serve
from . import views

urlpatterns = [
    path('',views.home,name="home"),
    path('notes/', include(('notes.urls','notes'),namespace='notes')),
    path('creators/', include(('creators.urls','creators'),namespace='creators')),
    path('gptutils/', include(('gptutils.urls','recipes'),namespace='gptutils')),
    path('about/',views.about,name="about"),
    path('search/',views.about,name="search"),
    path('admin/', admin.site.urls),
]

# ... the rest of your URLconf goes here ...

if settings.DEBUG:
    urlpatterns += [
        re_path(
            r"^media/(?P<path>.*)$",
            serve,
            {
                "document_root": settings.MEDIA_ROOT,
            },
        ),
    ]
