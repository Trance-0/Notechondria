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
from . import views
from django.contrib import admin
from django.urls import include, path
from django.conf.urls.static import static

urlpatterns = [
    path('',views.home,name="home"),
    path('notes/', include(('notes.urls','notes'),namespace='notes')),
    path('gptutils/', include(('gptutils.urls','recipes'),namespace='gptutils')),
    path('about/',views.about,name="about"),
    path('admin/', admin.site.urls),
]+ static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
