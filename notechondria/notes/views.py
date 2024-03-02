"""
This is where you handle requests (front-end)
Also, you can modify models here (back-end)
"""
import logging

from django.http import HttpResponseNotFound
from notechondria.utils import get_object_or_None,generate_unique_id,load_form_error_to_messages
from django.shortcuts import get_object_or_404, redirect, render
from django.contrib.auth.decorators import login_required
from creators.models import Creator
from .models import Note, NoteBlock, NoteIndex, Tag, ValidationRecord, NoteBlockTypeChoices, NoteIndex
from .forms import NoteForm, NoteBlockForm
from django.contrib import messages

logger=logging.getLogger()

# Create your views here.

@login_required
def list_notes(request):
    """ render list of notes for user, search will using post requests

    Returns:
        request.GET: return list of notes and noteblocks created by user, or 404 if user not exists.
        request.POST: return searched result of the post request.
    """
    context={}
    owner_id = get_object_or_404(Creator, user_id=request.user)
    # in this step, we only add user's notes
    note_list= NoteIndex.objects.filter(note_id__creator_id=owner_id)
    # for other queries, use NoteIndex.objects.union()
    context["note_list"]=note_list
    # and user's noteblock
    noteblock_list= NoteBlock.objects.filter(creator_id=owner_id)
    # for other queries, use NoteIndex.objects.union()
    context["noteblock_list"]=noteblock_list
    return render(request,"note_list.html",context=context)


# model-formsets reference: https://docs.djangoproject.com/en/4.2/topics/forms/modelforms/#model-formsets
@login_required
def edit_note(request, note_id):
    """I will not use formset because there are too many restrictions and don't support many to many field.
    
    Args:
        note_id: id of Note

    Returns:
        request: return note editor with note meta form, noteIndex as handlers.
    
    """
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
    # process get request
    else:
        # test if note exist
        note_instance = get_object_or_404(Note, pk=note_id)
        context["note_form"] = NoteForm(instance=note_instance)
        # noteblocks
        note_indexes= NoteIndex.objects.filter(note_id=note_instance).order_by("index")
        context["noteblocks_list"] = note_indexes
    return render(request,"note_editor.html",context=context)

@login_required
def edit_block(request, noteblock_id):
    """Edit single block using htmx, also responsible for adding new noteblock if noteblock_id given is -1.
    
    Args:
        noteblock_id: id of NoteBlock object, -1 if to create a new block

    Returns:
        request: return saved htmx form
    
    """
    context={}
    owner_id= get_object_or_None(Creator, user_id=request.user)
    # early terminate
    if owner_id==None:
        messages.error(request,"User not found.")
        return render(request,"htmx_edit_noteblock.html",context=context)
    # create new noteblock
    noteblock_form = NoteBlockForm()
    if request.method=="POST":
        # we might at feature photo form each post, so just assume have files
        if not noteblock_form.is_valid():
            load_form_error_to_messages(request,noteblock_form)
    # render get request
    # update if there exists an instance for requested
    if noteblock_id!=-1:
        noteblock_instance=get_object_or_None(NoteBlock,pk=noteblock_id)
        if noteblock_instance==None:
            messages.error("Noteblock with id not found")
            return render(request,"htmx_edit_noteblock.html",context=context)
        # check permission
        if noteblock_instance.creator_id!=owner_id:
            messages.error("You don't have permission to edit this noteblock")
            return render(request,"htmx_edit_noteblock.html",context=context)
        noteblock_form = NoteBlockForm(instance=noteblock_instance)
    context["noteblock_form"]=noteblock_form
    return render(request,"htmx_edit_noteblock.html",context=context)

@login_required
def create_note(request):
    """ for quick, I mean really quick, this is function should not be used in note editor

    Returns:
        request.GET: return htmx form (model), or error message html
        request.POST: redirect to new page

    directly render model for creating notes, this function must be called by ajax(htmx)
    """
    # test for user
    owner_id = get_object_or_None(Creator, user_id=request.user)
    if request.method=="POST":
        if owner_id==None:
            messages.error(request,"User not found!")
            return HttpResponseNotFound() 
        note_form=NoteForm(request.POST,request.FILES)
        if not note_form.is_valid():
            messages.error(request, f"invalid form submission")
            return redirect("notes:list_notes")
        note_instance=note_form.save(commit=False)
        note_instance.creator_id=owner_id
        note_instance.sharing_id=generate_unique_id(Note,"sharing_id")
        note_instance.save()
        # create header noteblock
        note_block_instance=NoteBlock.objects.create(creator_id=owner_id,
                                                     note_id=note_instance,
                                                     block_type=NoteBlockTypeChoices.TITLE,
                                                     is_AI_generated=False)
        # create handler
        NoteIndex.objects.create(note_id=note_instance,index=0,noteblock_id=note_block_instance)
        messages.success(request, f'Create note with title: {note_instance.title} success!')
        return redirect("notes:edit_note",note_id=note_instance.id)
    # for get request
    if owner_id==None:
        messages.error(request,"User not found!")
        return render(request,"message_display.html")
    return render(request,"htmx_create_note.html",context={"note_form" :NoteForm()})

@login_required
def create_block(request):
    """ for quick, I mean really quick, this is function should not be used in note editor
    this is a htmx function directly render model for creating note block, this function must be called by ajax(htmx)
    """
    context={}
    # test for user
    owner_id = get_object_or_None(Creator, user_id=request.user)
    if owner_id==None:
        messages.error(request,"User not found!")
        return render(request,"message_display.html")
    if request.method=="POST":
        noteBlock_form=NoteBlockForm(request.POST,request.FILES)
        context["noteblock_form"]=noteBlock_form
        if not noteBlock_form.is_valid():
            messages.error(request, f"invalid note block form submitted.")
            return redirect("notes:list_notes")
        noteBlock_instance=noteBlock_form.save(commit=False)
        noteBlock_instance.creator_id=owner_id
        noteBlock_instance=noteBlock_instance.save()
        messages.success(request, f'Create noteblock: {noteBlock_instance} success!')
        return redirect("notes:list_notes")
    else:
        context["noteblock_form"]=NoteBlockForm()
    return render(request,"htmx_create_noteblock.html",context=context)

@login_required
def reorder_blocks(request):
    """ sortable to setup order of noteblocks in note.
    reference: https://htmx.org/examples/sortable/
    
    """

# view note or snippets

@login_required
def view_note(request,note_id):
    """ render list of notes"""
    raise Exception('Not implemented yet')

@login_required
def view_block(request,noteblock_id):
    """ render list of notes"""
    raise Exception('Not implemented yet')
