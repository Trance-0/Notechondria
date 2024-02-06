import random
from django.shortcuts import get_object_or_404, redirect, render
from django.contrib.auth.decorators import login_required

from django.contrib import messages
from creators.models import Creator
from .forms import ConversationForm,MessageForm
from .models import Conversation,Message
from gpt_request_parser import generate_message

# Create your views here.

# @login_required
# def one_chat(request):
#     """ render main chat page"""
#     owner_id = Creator.objects.get(user_id=request.user)
#     # get list of conversations
#     return render(request, "conversation.html", {"user":owner_id })

@login_required
def gptutils(request):
    """ render main chat page"""
    owner_id = Creator.objects.get(user_id=request.user)
    # get list of conversations
    conversations_list=Conversation.objects.filter(creator_id=owner_id)
    return render(request, "conversation.html", context={"user":owner_id,
                                                         "conversations_list":conversations_list
                                                         })

@login_required
def send(request,pk):
    """ send image request """
    return redirect("gptutils:main")

@login_required
def get_chat(request,conv_pk):
    owner_id = Creator.objects.get(user_id=request.user)
    # get list of conversations
    conversations_list=Conversation.objects.filter(creator_id=owner_id)
    cur_conversation=get_object_or_404(Conversation,pk=conv_pk)
    if cur_conversation.owner_id!=owner_id:
        messages.error(request,f'no permission for edit the conversation')
        return redirect("gptutils:main")
    """ send text request """
    # processing sending
    if request.method=="POST":
        # permission check
        message_form=MessageForm(request.POST, request.FILES)
        if not message_form.is_valid():
            messages.error(request,f'invalid conversation')
            return redirect("gptutil:get_chat",conv_pk)
        message_instance=message_form.save(commit=False)
        message_instance.conversation_id=cur_conversation
        message_instance.save()
        generate_message(cur_conversation)
    # processing response
    messages_list=Message.objects.filter(conversations_id=cur_conversation)
    return render(request, "conversation.html",context={"user":owner_id,
                                                        "conversations_list":conversations_list,
                                                        "cur_conversation":cur_conversation,
                                                        "messages_list":messages_list})

@login_required
def create_chat(request):
    """ send text request """
    if request.method=="POST":
        chat_form=ConversationForm(request.POST, request.FILES)
        chat_instance=chat_form.save(commit=False)
        chat_instance.sharing_id=generate_chat_id()
        chat_instance.save()
        return redirect("gptutils:get_chat",conv_pk=chat_instance)
    return redirect("gptutils:main")

def generate_chat_id()->str:    
    """ Generate random key with length

    Attribute:
        characters: the character set of 
    
    Args:
        length: default generate code with length 10

    Returns:
        random string with give size
    
    """
    characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-'
    n=len(characters)
    res=''
    for _ in range(8):
        res+=characters[random.randint(0,n-1)]
    while Conversation.objects.filter(sharing_id=res).exists():
        res=''
        for _ in range(8):
            res+=characters[random.randint(0,n-1)]
    return res

    