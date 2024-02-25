"""
This is where you handle requests (front-end)
Also, you can modify models here (back-end)
"""
from django.shortcuts import render
from django.contrib.auth.decorators import login_required

# Create your views here.

@login_required
def list_notes(request):
    """ render list of notes"""
    raise Exception('Not impelemented yet')

# note creating

@login_required
def new_notes(request):
    """ render list of notes"""
    return render(request,"note_editor.html")
    # return render(request,"monaco_official_sample.html")

@login_required
def quick_notes(request):
    """ render list of notes"""
    raise Exception('Not impelemented yet')

# view note or snippets

@login_required
def get_note(request):
    """ render list of notes"""
    raise Exception('Not impelemented yet')

@login_required
def view_notes(request):
    """ render list of notes"""
    raise Exception('Not impelemented yet')