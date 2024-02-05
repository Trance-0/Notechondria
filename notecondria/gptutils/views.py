import random
from django.shortcuts import redirect, render
from django.contrib.auth.decorators import login_required

from creators.models import Creator
from .forms import ConversationForm
from .models import Conversation

# Create your views here.

@login_required
def one_chat(request):
    """ render main chat page"""
    owner_id = Creator.objects.get(user_id=request.user)
    # get list of conversations
    return render(request, "conversation.html", {"user":owner_id })

@login_required
def gptutils(request):
    """ render main chat page"""
    owner_id = Creator.objects.get(user_id=request.user)
    # get list of conversations
    conversations=Conversation.objects.filter(creator_id=owner_id)
    return render(request, "conversation.html", context={"user":owner_id,
                                                         "conversation_list":conversations
                                                         })

@login_required
def send(request,pk):
    """ send image request """
    return redirect("gptutils:main")

@login_required
def get_chat(request,pk):
    """ send text request """
    return redirect("gptutils:main")

@login_required
def create_chat(request):
    """ send text request """
    if request.method=="POST":
        chat_form=ConversationForm(request.POST, request.FILES)
    return redirect("gptutils:get_chat")

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