"""
This is where you handle requests (front-end)
Also, you can modify models here (back-end)
"""

from django.shortcuts import render
from django.contrib import messages
from django.conf import settings

def home(request):
    """render default home page"""
    return render(request,'index.html',{})

def about(request):
    """render static about page"""
    return render(request,'about.html',{})

def search(request):
    """render dynamic search page, process get requests only"""
    messages.warning(request, "function not implemented.")
    return render(request,'index.html',{})

def is_offline(request):
    """context processor for OFFLINE variable in settings
    
    reference:https://stackoverflow.com/questions/433162/can-i-access-constants-in-settings-py-from-templates-in-django
    """
    return {'is_offline': settings.OFFLINE}