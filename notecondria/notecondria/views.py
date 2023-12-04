"""
This is where you handle requests (front-end)
Also, you can modify models here (back-end)
"""

from django.shortcuts import render

def home(request):
    """render default home page"""
    return render(request,'index.html',{})

def about(request):
    """render static about page"""
    return render(request,'about.html',{})
