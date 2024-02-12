import logging
import random
from django.http import JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.contrib.auth.decorators import login_required

from django.contrib import messages
from creators.models import Creator
from .forms import ConversationFormS, ConversationFormL, MessageForm
from .models import Conversation, Message, GPTModelChoices
from .gpt_request_parser import generate_message

logger=logging.getLogger()

# Create your views here.

# @login_required
# def one_chat(request):
#     """ render main chat page"""
#     owner_id = Creator.objects.get(user_id=request.user)
#     # get list of conversations
#     return render(request, "conversation.html", {"user":owner_id })


@login_required
def gptutils(request):
    """render main chat page"""
    context=__get_basic_context(request)
    context["is_visual_model"]=True
    return render(request, "conversation.html", context=context)

@login_required
def get_chat(request, conv_pk):
    """ send text request """
    logger.debug(f'request from user {request.user}')
    # processing sending in AJAX (to be implement)
    context = __get_basic_context(request)
    cur_conversation = get_object_or_404(Conversation, id=conv_pk)
    context["cur_conversation"] = cur_conversation
    context["is_visual_model"] = (cur_conversation.model == GPTModelChoices.GPT4_V or 
                                    cur_conversation.model == GPTModelChoices.GPT4_VH 
                                    or cur_conversation.model == GPTModelChoices.GPT4_VL)
    if cur_conversation.creator_id != context["user"]:
        messages.error(request, f"no permission for edit the conversation")
        return redirect("gptutils:main")
    if request.method == "POST":
        # permission check
        message_form = MessageForm(request.POST, request.FILES)
        if not message_form.is_valid():
            for key, value in message_form.errors.items():
                messages.error(request, f"validation error on field {key},{value}")
            return redirect("gptutils:get_chat", conv_pk=conv_pk)
        message_instance = message_form.save(commit=False)
        message_instance.conversation_id = cur_conversation
        message_instance.save()
        response_json=generate_message(cur_conversation)
        if "error" in response_json:
            messages.error(request, f"open-ai error: {response_json}")
    # processing response
    messages_list = Message.objects.filter(conversation_id=conv_pk).order_by("created")
    context["messages_list"] = messages_list
    return render(request, "conversation.html", context=context)


@login_required
def create_chat(request):
    """create chat based on conversation form received from user"""
    # test for user
    owner_id = get_object_or_404(Creator, user_id=request.user)
    if request.method == "POST":
        form_type = request.POST.get("form_type", "invalid")
        if form_type == "invalid":
            messages.error(request, f"form type not found or invalid")
        chat_form = (
            ConversationFormL(request.POST, request.FILES)
            if form_type == "advanced"
            else ConversationFormS(request.POST)
        )
        if chat_form.is_valid():
            chat_instance = chat_form.save(commit=False)
            chat_instance.sharing_id = __generate_chat_id()
            chat_instance.creator_id = owner_id
            chat_instance.save()
            return redirect("gptutils:get_chat", conv_pk=chat_instance.id)
        else:
            messages.warning(request,f"invalid parameters found")
    return redirect("gptutils:main")

@login_required
def fast_chat(request):
    """create chat based on conversation form received from user"""
    # test for user
    owner_id = get_object_or_404(Creator, user_id=request.user)
    if request.method == "POST":
        # permission check
        message_form = MessageForm(request.POST, request.FILES)
        if not message_form.is_valid():
            messages.error(request, f"invalid message")
            return redirect("gptutils:main")
        message_instance = message_form.save(commit=False)
        cur_conversation=Conversation.objects.create(creator_id=owner_id,
                                                     sharing_id=__generate_chat_id(),
                                                     model=GPTModelChoices.GPT4_V if message_instance.image else GPTModelChoices.GPT4_1106)
        message_instance.conversation_id = cur_conversation
        message_instance.save()
        ai_response=generate_message(cur_conversation)
        if not "error" in ai_response:
            return redirect("gptutils:get_chat", conv_pk=cur_conversation.id)
        else:
            messages.warning(request,f"Error when generating response {ai_response['error']}")
    else:
        messages.warning(request,f"invalid parameters found")
    return redirect("gptutils:main")

@login_required
def edit_chat(request,conv_pk):
    """redirect to edit chat page"""
    # test for user
    owner_id = get_object_or_404(Creator, user_id=request.user)
    chat_instance = get_object_or_404(Conversation, id=conv_pk)
    if chat_instance.creator_id!=owner_id:
        messages.error(request, f"You don't have access to the chat")
        return redirect("gptutils:main")
    if request.method == "POST":
        form_type = request.POST.get("form_type", "invalid")
        if form_type == "invalid":
            messages.error(request, f"form type not found or invalid")
        chat_form = (
            ConversationFormL(request.POST, request.FILES)
            if form_type == "advanced"
            else ConversationFormS(request.POST)
        )
        chat_instance = chat_form.save(commit=False)
        chat_instance.sharing_id = __generate_chat_id()
        chat_instance.creator_id = owner_id
        chat_instance.save()
        return redirect("gptutils:get_chat", conv_pk=chat_instance.id)
    return render(request,"htmx_edit_chat_form.html",context={"edit_form":ConversationFormL(chat_instance)})

@login_required
def edit_message(request,conv_pk,message_pk):
    """redirect to edit chat modal, process handel by htmx"""
    # test for user
    # owner_id = get_object_or_404(Creator, user_id=request.user)
    # chat_instance = get_object_or_404(Conversation, id=conv_pk)
    # if chat_instance.owner_id!=owner_id:
    #     messages.error(request, f"You don't have access to the chat")
    #     return redirect("gptutils:main")
    # if request.method == "POST":
    #     form_type = request.POST.get("form_type", "invalid")
    #     if form_type == "invalid":
    #         messages.error(request, f"form type not found or invalid")
    #     chat_form = (
    #         ConversationFormL(request.POST, request.FILES)
    #         if form_type == "advanced"
    #         else ConversationFormS(request.POST)
    #     )
    #     chat_instance = chat_form.save(commit=False)
    #     chat_instance.sharing_id = __generate_chat_id()
    #     chat_instance.creator_id = owner_id
    #     chat_instance.save()
    #     return redirect("gptutils:get_chat", conv_pk=chat_instance.id)
    # process get request
    # render page
    return render(request,"edit_chat_form.html",context={"edit_form":ConversationFormL(chat_instance)})


@login_required
def delete_chat(request, conv_pk):
    """send text request"""
    if request.method == "POST":
        # validate ownership
        chat_instance = get_object_or_404(Conversation, id=conv_pk)
        owner_id = get_object_or_404(Creator, user_id=request.user)
        if chat_instance.owner_id == owner_id:
            messages.success(request,f"Successfully delete the chat with title {chat_instance.title}")
            chat_instance.delete()
            return redirect("gptutils:main")
        else:
            messages.warning(request,f"Current user don't have the permission to delete the chat")
    return redirect("gptutils:get_chat", conv_pk=conv_pk)


def __generate_chat_id() -> str:
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
    while Conversation.objects.filter(sharing_id=res).exists():
        res = ""
        for _ in range(8):
            res += characters[random.randint(0, n - 1)]
    return res


def __get_basic_context(request) -> dict:
    context = {}
    context["user"] = Creator.objects.get(user_id=request.user)
    context["create_form_simple"] = ConversationFormS()
    context["create_form_advanced"] = ConversationFormL()
    context["message_form"] = MessageForm()
    # get list of conversations
    context["conversations_list"] = Conversation.objects.filter(
        creator_id=context["user"]
    ).order_by("last_use")
    return context
