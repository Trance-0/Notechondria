"""
This is where you handle requests (front-end)
Also, you can modify models here (back-end)
"""
import logging
import random
from django.forms import modelformset_factory
from django.shortcuts import get_object_or_404, redirect, render
from django.contrib.auth.decorators import login_required
from creators.models import Creator
from .models import Note, NoteBlock, NoteIndex, Tag, ValidationRecord
from .forms import NoteForm, NoteBlockForm
from django.contrib import messages

logger=logging.getLogger()

# Create your views here.

@login_required
def list_notes(request):
    """ render list of notes for user"""

    return redirect("home")


# model-formsets reference: https://docs.djangoproject.com/en/4.2/topics/forms/modelforms/#model-formsets
@login_required
def edit_note(request, note_id):
    """I will not use formset because there are too many restrictions and don't support many to many field."""
    # load basic context
    owner_id = get_object_or_404(Creator, user_id=request.user)
    context={}
    if request.method == "POST":
        # we might at feature photo form each post, so just assume have files
        note_form = NoteForm(
            request.POST, request.FILES, instance=get_object_or_404(Note, pk=note_id)
        )
        if not note_form.is_valid():
            for key, value in note_form.errors.items():
                messages.error(request, f"validation error on field {key}:{[error for error in value]}")
            return redirect("notes:edit_note", note_id=note_id)
        note_instance = note_form.save(commit=False)
        # test ownership
        if note_instance.owner_id != owner_id:
            messages.warning(request,"You don't have access to this page.")
            return redirect("home")
        note_instance.save()
        # success
        messages.success(request,"edit note block success")
        context["note_form"]=note_form
    else:
        # test if note exist
        note_instance = get_object_or_404(Note, pk=note_id)
        context["note_form"] = NoteForm(instance=note_instance)
        # noteblocks
        note_indexes= NoteIndex.objects.filter(note_id=note_instance).order_by("index")
        context["noteblocks_list"] = [idx.note_id for idx in note_indexes]
    return render(request,"note_editor.html",context=context)

def __generate_note_id() -> str:
    """Generate random key with length

    Attribute:
        characters: the character set of

    Args:
        length: default generate code with length 10

    Returns:
        random string with give size

    """
    characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-"
    n = len(characters)
    res = ""
    for _ in range(8):
        res += characters[random.randint(0, n - 1)]
    while Note.objects.filter(sharing_id=res).exists():
        res = ""
        for _ in range(8):
            res += characters[random.randint(0, n - 1)]
    return res

@login_required
def create_note(request):
    """ for quick, I mean really quick
    directly render model for creating notes, this function must be called by ajax(htmx)
    """
    # test for user
    owner_id = get_object_or_404(Creator, user_id=request.user)
    if request.method=="POST":
        note_form=NoteForm(request.POST,request.FILES)
        if not note_form.is_valid():
            messages.error(request, f"invalid form submission")
            return redirect("notes:list_notes")
        note_instance=note_form.save(commit=False)
        note_instance.creator_id=owner_id
        note_instance.sharing_id=__generate_note_id()
        
        note_instance.save()
        messages.success(request, f'Create note with title: {note_instance.title} success!')
        return redirect("notes:edit_note",note_id=note_instance.id)
    return render(request,"htmx_create_note.html",context={"note_form" :NoteForm()})

@login_required
def create_block(request):
    """ for quick, I mean really quick
    directly render model for creating note block, this function must be called by ajax(htmx)
    """
    context={}
    # test for user
    owner_id = get_object_or_404(Creator, user_id=request.user)
    if request.method=="POST":
        noteBlock_form=NoteBlockForm(request.POST,request.FILES)
        context["noteblock_form"]=noteBlock_form
        if not noteBlock_form.is_valid():
            messages.error(request, f"invalid note block form submitted.")
            return redirect("notes:list_notes")
        noteBlock_instance=noteBlock_form.save(commit=False)
        noteBlock_instance.creator_id=owner_id
        noteBlock_instance.save()
        messages.success(request, f'Create note with title: {noteBlock_instance.title} success!')
        return redirect("notes:list_notes")
    else:
        context["noteblock_form"]=NoteBlockForm()
    return render(request,"htmx_create_noteblock.html",context=context)


# view note or snippets

@login_required
def get_note(request):
    """ render list of notes"""
    raise Exception('Not impelemented yet')

@login_required
def view_notes(request):
    """ render list of notes"""
    raise Exception('Not impelemented yet')