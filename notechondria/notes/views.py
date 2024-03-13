"""
This is where you handle requests (front-end)
Also, you can modify models here (back-end)
"""
import json
import logging

from django.http import HttpResponseNotFound
from django.views.decorators.http import require_POST, require_GET
from notechondria.utils import get_object_or_None,generate_unique_id,load_form_error_to_messages,check_is_creator
from django.shortcuts import get_object_or_404, redirect, render
from django.contrib.auth.decorators import login_required
from creators.models import Creator
from .models import Note, NoteBlock, NoteIndex, Tag, ValidationRecord, NoteBlockTypeChoices, NoteIndex
from .forms import NoteForm, NoteBlockForm
from django.contrib import messages

logger=logging.getLogger()

# Create your views here.

@login_required
@require_GET
def list_notes(request):
    """ render list of notes for user, search will using post requests

    Returns:
        request.GET: return list of notes and noteblocks created by user, or 404 if user not exists.
        request.POST: return searched result of the post request.
    """
    context={}
    owner_id = get_object_or_404(Creator, user_id=request.user)
    # in this step, we only add user's notes
    note_list= NoteIndex.objects.filter(note_id__creator_id=owner_id).distinct('note_id')
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
    this function supports for block editor and code editor
    
    Args:
        note_id: id of Note

    Returns:
        request: return note editor with note meta form, noteIndex as handlers.
    
    """
    context={}
    # load basic context
    owner_id,note_instance=check_is_creator(request, Note, "edit", pk=note_id)
    # test ownership
    if owner_id==None:
        messages.warning(request,"You don't have access to this page.")
        return redirect("home")
    if request.method == "POST":
        # default save method is for block_editor
        save_method=request.POST.get("method", "form")
        if save_method=="form":
            # we might at feature photo form each post, so just assume have files
            note_form = NoteForm(
                request.POST, request.FILES, instance=note_instance
            )
            if not note_form.is_valid():
                for key, value in note_form.errors.items():
                    messages.error(request, f"validation error on field {key}:{[error for error in value]}")
                return redirect("notes:edit_note", note_id=note_id)
            note_instance = note_form.save(commit=False)
            note_instance.save()
            # success
            messages.success(request,"edit note block success")
            context["note_form"]=note_form
        elif save_method=="code":
            # debug
            logger.info(request.POST)
            
            # test if note exist
            context["note_form"] = NoteForm(instance=note_instance)
            note_indexes= NoteIndex.objects.filter(note_id=note_instance).order_by("index")
            context["noteblocks_list"] = note_indexes
            context["note_md"]='\n'.join([i.noteblock_id.get_md_str() for i in note_indexes])
            return render(request,"note_code_editor.html",context=context)
    # process get request
    else:
        # test if note exist
        context["note_form"] = NoteForm(instance=note_instance)
        # noteblocks
        note_indexes= NoteIndex.objects.filter(note_id=note_instance).order_by("index")
        context["noteblocks_list"] = note_indexes
        context["note_md"]='\n'.join([i.noteblock_id.get_md_str() for i in note_indexes])
    return render(request,"note_editor.html",context=context)

@login_required
def edit_block(request, noteblock_id):
    """Edit single block using htmx, not responsible for edit block reference (NoteIndex) and this feature should be implement in the future.

    Args:
        note_handle_id: id of NoteBlock handle object, creation of note block on the process is handled by insert_block function, if the current handle is not root handle, then we may return a **reference form** (to be implemented)

    Returns:
        request: return saved htmx form
    
    """
    context={}
    owner_id,prev_instance=check_is_creator(request, NoteBlock, "edit", pk=noteblock_id)
    if owner_id==None:
        return render(request,"htmx_edit_noteblock.html",context=context)
    # create new noteblock
    noteblock_form = NoteBlockForm()
    # load handle parameters
    # check root handle
    if prev_instance.note_id==None:
        messages.error(request,"Noteblock is corrupted, note_id not found where it is expected to be found.")
        return render(request,"htmx_edit_noteblock.html",context=context)
    note_handle_instance=get_object_or_None(NoteIndex,note_id=prev_instance.note_id, noteblock_id=prev_instance)
    # load noteblock handle
    context["noteblock_handle"]=note_handle_instance
    if request.method=="POST":
        save_method=request.POST.get("method", "form")
        if save_method=="form":
            noteblock_form=NoteBlockForm(request.POST,request.FILES,instance=prev_instance)
            # we might at feature photo form each post, so just assume have files
            if not noteblock_form.is_valid():
                load_form_error_to_messages(request,noteblock_form)
                return render(request,"htmx_edit_noteblock.html",context=context)
            noteblock_instance=noteblock_form.save(commit=False)
            noteblock_instance.is_AI_generated=request.POST.get('is_AI_generated', '')=='on'
            # test creator id
            # creator_id= get_object_or_None(Creator, user_id=noteblock_form.cleaned_data["creator_id"])
            # if creator_id!=owner_id:
            #     messages.error(request,"Incorrect permission found, we have not implement ownership transfer yet.")
            #     return render(request,"htmx_edit_noteblock.html",context=context)
            noteblock_instance.creator_id=prev_instance.creator_id
            # test note id
            # note_id=get_object_or_None(Note,pk=noteblock_form.cleaned_data["note_id"])
            # if note_id!=prev_instance.note_id:
            #     messages.error(request,"Incorrect note found, we have not implement note transfer yet.")
            #     return render(request,"htmx_edit_noteblock.html",context=context)
            noteblock_instance.note_id=prev_instance.note_id
            noteblock_instance.save()
            noteblock_form = NoteBlockForm(instance=noteblock_instance,auto_id=f"nb_{noteblock_instance.id}_id_%s")
        elif save_method=="code":
            # debug
            logger.info(request.POST)
            
            context["noteblock_form"]=noteblock_form
            context["noteblock_md"]=noteblock_form.instance.get_md_str()
            return render(request,"note_code_editor.html",context=context)
    # render get request
    # update if there exists an instance for requested
    else:
        noteblock_form = NoteBlockForm(instance=prev_instance,auto_id=f"nb_{prev_instance.id}_id_%s")
    context["noteblock_form"]=noteblock_form
    context["noteblock_md"]=noteblock_form.instance.get_md_str()
    return render(request,"htmx_edit_noteblock.html",context=context)

@login_required
@require_POST
def insert_block(request, note_id, noteblock_id):
    """insert before the noteblock_id and create new noteblock with handler, process post request only (security)
    No self referencing should be allowed, or the code needs to be change dramatically. and insert reference should be implement separately.
    
    Args:
        noteblock_id: id of NoteBlock object that we need to insert before, 65535 for insert on the last.

    Returns:
        htmx note block editor to refresh handle references
    
    """
    context={}
    if request.method=="POST":
        owner_id,note_instance= check_is_creator(request, Note, "insert block", pk=note_id)
        if owner_id==None:
            return render(request,"note_block_editor.html",context=context)
        noteblock_handlers=list(NoteIndex.objects.filter(note_id=note_id).order_by("index"))
        new_block=NoteBlock.objects.create(creator_id=owner_id,note_id=note_instance,block_type=NoteBlockTypeChoices.TEXT,is_AI_generated=False,text="")
        # add to end
        if noteblock_id==65535:
            NoteIndex.objects.create(note_id=note_instance,index=noteblock_handlers[-1].index+1,noteblock_id=new_block)
            # messages.success("insert section on end success")
            # reload context
            context["noteblocks_list"]=NoteIndex.objects.filter(note_id=note_id).order_by("index")
            return render(request,"note_block_editor.html",context=context)
        
        # do normal moving and insert
        noteblock_instance=get_object_or_None(NoteBlock, pk=noteblock_id)
        if noteblock_instance==None:
            messages.error(request,"noteblock instance not found.")
            return render(request,"note_block_editor.html",context=context)
        noteblock_target_handler=get_object_or_None(NoteIndex,note_id=note_id,noteblock_id=noteblock_id)
        if noteblock_target_handler==None:
            messages.error(request,"noteblock handle not found")
            return render(request,"note_block_editor.html",context=context)
        idx,n=noteblock_handlers.index(noteblock_target_handler),len(noteblock_handlers)
        if len(noteblock_handlers)==0:
            return render(request,"note_block_editor.html",context=context)
        if idx==-1:
            messages.error(request,"idx out of range? how did you get this error?")
            return render(request,"note_block_editor.html",context=context)
        # move index after idx
        for i in range(idx,n):
            cur_handle=noteblock_handlers[i]
            cur_handle.index+=1
            cur_handle.save()
        NoteIndex.objects.create(note_id=note_instance,index=idx,noteblock_id=new_block)
        # messages.success("insert section on end success")
        # reload context
        context["noteblocks_list"]=NoteIndex.objects.filter(note_id=note_id).order_by("index")
        context["note_form"]=NoteForm(instance=note_instance)
    return render(request,"note_block_editor.html",context=context)

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
def reorder_blocks(request,note_id):
    """ sortable to setup order of noteblocks in note.
    reference: https://htmx.org/examples/sortable/

    Attributes:
        note_id: the id for the note to reorder

    Returns:
        htmx note block editor template.
    
    """
    context={}
    # reordering

    # test if note exist
    _,note_instance = check_is_creator(request, Note, "reorder", pk=note_id)
    if note_instance==None:
        messages.error("Note not found")
        return render(request, "note_block_editor_core.html",context)
    context["note_form"] = NoteForm(instance=note_instance)
    note_indexes= list(NoteIndex.objects.filter(note_id=note_instance).order_by("index"))
    logger.info(f'received item: {request.POST.get("item")}')
    order_list=json.loads(request.POST.get("item"))
    if "length" not in order_list or int(order_list["length"])!=len(note_indexes):
        messages.error("Note size mismatched with reorder list")
        return render(request, "note_block_editor_core.html",context)
    # load new order
    for i,e in enumerate(note_indexes):
        e.index=int(order_list[str(i)])
        e.save()
    note_indexes= NoteIndex.objects.filter(note_id=note_instance).order_by("index")
    context["noteblocks_list"] = note_indexes
    return render(request, "note_block_editor_core.html",context)

# view note or snippets

@login_required
def view_note(request,note_id):
    """ render list of notes"""
    raise Exception('Not implemented yet')

@login_required
def view_block(request,noteblock_id):
    """ render list of notes"""
    raise Exception('Not implemented yet')
