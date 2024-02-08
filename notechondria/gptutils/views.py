import random
from django.shortcuts import get_object_or_404, redirect, render
from django.contrib.auth.decorators import login_required

from django.contrib import messages
from creators.models import Creator
from .forms import ConversationFormS, ConversationFormL, MessageForm
from .models import Conversation, Message
from .gpt_request_parser import generate_message

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
    return render(request, "conversation.html", context=__get_basic_context(request))


@login_required
def send(request, conv_pk):
    """send image request"""
    return redirect("gptutils:get_chat", conv_pk)


@login_required
def get_chat(request, conv_pk):
    context = __get_basic_context(request)
    cur_conversation = get_object_or_404(Conversation, pk=conv_pk)
    context["cur_conversation"] = cur_conversation
    if cur_conversation.creator_id != context["user"]:
        messages.error(request, f"no permission for edit the conversation")
        return redirect("gptutils:main")
    """ send text request """
    # processing sending
    if request.method == "POST":
        # permission check
        message_form = MessageForm(request.POST, request.FILES)
        if not message_form.is_valid():
            messages.error(request, f"invalid conversation")
            return redirect("gptutils:get_chat", conv_pk=conv_pk)
        message_instance = message_form.save(commit=False)
        message_instance.conversation_id = cur_conversation
        message_instance.save()
        generate_message(cur_conversation)
    # processing response
    messages_list = Message.objects.filter(conversation_id=conv_pk)
    context["messages_list"] = messages_list
    return render(request, "conversation.html", context=context)


@login_required
def create_chat(request):
    """send text request"""
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
        chat_instance = chat_form.save(commit=False)
        chat_instance.sharing_id = __generate_chat_id()
        chat_instance.creator_id = owner_id
        chat_instance.save()
        return redirect("gptutils:get_chat", conv_pk=chat_instance.id)
    return redirect("gptutils:main")


@login_required
def delete_chat(request, conv_pk):
    """send text request"""
    if request.method == "POST":
        # validate ownership
        chat_instance = get_object_or_404(Conversation, pk=conv_pk)
        owner_id = get_object_or_404(Creator, user_id=request.user)
        if chat_instance.owner_id == owner_id:
            messages.success()
            chat_instance.delete()
            return redirect("gptutils:main")
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
    )
    return context
