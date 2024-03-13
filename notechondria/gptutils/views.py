from datetime import datetime
from django.utils import timezone
import logging
from notechondria.utils import check_is_creator, generate_unique_id, get_object_or_None,load_form_error_to_messages
from django.http import StreamingHttpResponse
from django.views.decorators.http import require_POST,require_GET
from django.shortcuts import get_object_or_404, redirect, render
from django.contrib.auth.decorators import login_required

from django.contrib import messages
from creators.models import Creator
from .forms import ConversationFormS, ConversationFormL, MessageForm
from .models import Conversation, Message, GPTModelChoices, MessageRoleChoices
from .gpt_request_parser import generate_message,add_token, generate_stream_message

logger=logging.getLogger()

# Create your views here.

# @login_required
# def one_chat(request):
#     """ render main chat page"""
#     owner_id = Creator.objects.get(user_id=request.user)
#     # get list of conversations
#     return render(request, "conversation.html", {"user":owner_id })

####################################################################
# Cheat sheet for filtering in django model:
# Greater than:
# Person.objects.filter(age__gt=20)
# Greater than or equal to:
# Person.objects.filter(age__gte=20)
# Less than:
# Person.objects.filter(age__lt=20)
# Less than or equal to:
# Person.objects.filter(age__lte=20)
####################################################################

@login_required
@require_GET
def gptutils(request):
    """render main chat page"""
    context=__get_basic_context(request)
    context["is_visual_model"]=True
    return render(request, "conversation.html", context=context)

@login_required
def get_chat(request, conv_pk):
    """ send text request when request is get, return the chat page, when is post, add new message and set completion
    
    Args:
        conv_pk: primary key for Conversation objects

    Returns:
        request.POST:
            streaming: return htmx message pair for streaming (100ms)
            non-streaming: reload page until request to openAI is complete (5s on average)
        request.GET:
            streaming: return infinite scrolling result (default load 10 more messages)
    """
    logger.info(f'request from user {request.user}')
    # processing sending in AJAX (to be implement)
    context = __get_basic_context(request)
    cur_conversation = get_object_or_404(Conversation, id=conv_pk)
    context["cur_conversation"] = cur_conversation
    context["is_visual_model"] = cur_conversation.is_visual_model()
    if cur_conversation.creator_id != context["user"]:
        messages.error(request, f"no permission for edit the conversation")
        return redirect("gptutils:main")
    if request.method == "POST":
        # permission check
        message_form = MessageForm(request.POST, request.FILES)
        if not message_form.is_valid():
            load_form_error_to_messages(request,message_form)
            return render(request, "conversation.html", context=context)
        message_instance = message_form.save(commit=False)
        message_instance.conversation_id = cur_conversation
        response={}

        # processing plain request ajax
        if cur_conversation.model==GPTModelChoices.PLAIN:
            # for plain message, we do nothing but return rendered new message 
            messages_list=Message.objects.filter(conversation_id=conv_pk).order_by("-created")[:1]
            is_last_user=len(messages_list)==0 or messages_list[0].role==MessageRoleChoices.USER
            if is_last_user:
                message_instance.role=MessageRoleChoices.ASSISTANT
            message_instance.save()
            context["messages_list"] = [message_instance]
            # if request is post, then render new pair of message.
            if request.META.get('HTTP_HX_REQUEST'):
                return render(request, "htmx_message_blocks.html", context=context)
        
        # for other AI model, we test for streaming, streaming is an ajax only feature.
        message_instance.save()
        is_streaming=request.POST.get("streaming",False)
        if is_streaming:
            # create dummy message, text cannot be null, so we set it to blank?
            dummy_message=Message.objects.create(conversation_id=cur_conversation,role=MessageRoleChoices.ASSISTANT,text="")
            context["user_msg"]=message_instance
            context["assist_msg"]=dummy_message
            return render(request, "htmx_message_pair_streaming.html", context=context)
        else:
            add_token(message_instance)
            response=generate_message(cur_conversation)
            if "error" in response:
                messages.error(request, f"open-ai error: {response}")
                # if there is error, we cannot do ajax to notify user yet
                # return render(request, "conversation.html", context=context)
                context["messages_list"] = []
                return render(request, "htmx_message_blocks.html", context=context)
            if request.META.get('HTTP_HX_REQUEST'):
                # get most recent message, you can save this query but I don't care.
                context["messages_list"] = Message.objects.filter(conversation_id=conv_pk).order_by("-created")[:2]
                return render(request, "htmx_message_blocks.html", context=context)
        # all post request for this function terminates here.

    # processing get request from htmx (infinite scroll section requests)
    if request.META.get('HTTP_HX_REQUEST'):
        # if request is get, then render new message for infinite scroll
        if request.method=="GET":
            # for the timezone, since our app is running in UTC, remember to change it if you want other timezone.
            after_time=datetime.strptime(request.GET.get("after",""),"%Y-%m-%d %H:%M[:%S[.%f][%Z]").replace(tzinfo=timezone.utc)
            messages_list = Message.objects.filter(conversation_id=conv_pk,created__lt=after_time).order_by("-created")[:10]
            context["messages_list"] = messages_list
            # specify infinite scroll 
            context["infinite_scroll"] = True
            return render(request, "htmx_message_blocks.html", context=context)
    
    # processing response normally, non ajax
    messages_list = Message.objects.filter(conversation_id=conv_pk).order_by("-created")[:10]
    context["messages_list"] = messages_list
    return render(request, "conversation.html", context=context)

@login_required
def get_stream_chat(request, conv_pk):
    """ send text request based on streaming, this function is a bit complex if we add login request
    so we directly allow all the users to make request with strict permission check

    Args:
        conv_pk: primary key for Conversation objects
    """
    # owner_id = get_object_or_None(Creator, user_id=request.user)
    # if owner_id==None:
    #     yield "User not found."
    #     return
    cur_conversation = get_object_or_None(Conversation, id=conv_pk)
    # if cur_conversation==None:
    #     yield "Conversation not found."
    #     return
    logger.info(f'requested streaming chat instance edit form with id {conv_pk}')
    # if cur_conversation.creator_id!=owner_id:
    #     yield "You don't have permission to streaming this conversation."
    #     return
    return StreamingHttpResponse(generate_stream_message(cur_conversation))


@login_required
def create_chat(request):
    """create chat based on conversation form received from user
    
    Args:
        request.POST only.

    Returns:
        redirect to char page if creation is success, else back to gptutils main page.
    """
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
            chat_instance.sharing_id = generate_unique_id(Conversation,"sharing_id")
            chat_instance.creator_id = owner_id
            chat_instance.save()
            return redirect("gptutils:get_chat", conv_pk=chat_instance.id)
        else:
            load_form_error_to_messages(request,chat_form)
    return redirect("gptutils:main")

@login_required
@require_POST
def fast_chat(request):
    """create chat based on conversation form received from user
    I don't want to do any ajax on this section cause it costs a lot of work and don't have much improvement.
    
    Args:
        request.POST only.

    Returns:
        redirect to char page if creation is success, else back to gptutils main page.
    """
    # test for user
    owner_id = get_object_or_404(Creator, user_id=request.user)
    message_form = MessageForm(request.POST, request.FILES)
    if not message_form.is_valid():
        messages.error(request, f"invalid message")
        return redirect("gptutils:main")
    message_instance = message_form.save(commit=False)
    cur_conversation=Conversation.objects.create(creator_id=owner_id,
                                                    sharing_id=generate_unique_id(Conversation,"sharing_id"),
                                                    model=GPTModelChoices.GPT4_V if message_instance.image else GPTModelChoices.GPT4_1106)
    message_instance.conversation_id = cur_conversation
    message_instance.save()
    add_token(message_instance)
    ai_response=generate_message(cur_conversation)
    if not "error" in ai_response:
        return redirect("gptutils:get_chat", conv_pk=cur_conversation.id)
    else:
        messages.warning(request,f"Error when generating response {ai_response['error']}")
    return redirect("gptutils:main")

@login_required
def edit_chat(request,conv_pk):
    """redirect to edit chat form for htmx request return form only"""
    # test for user
    owner_id,chat_instance =check_is_creator(request,Conversation, "edit conversation", id=conv_pk)
    logger.info(f'requested chat instance edit form with id {conv_pk}')
    if owner_id==None:
        return redirect("gptutils:main")
    if request.method == "POST":
        chat_form = ConversationFormL(request.POST, request.FILES,instance=chat_instance)
        # check instance consistency
        if not chat_form.is_valid():
            load_form_error_to_messages(request,chat_form)
        elif chat_form.instance.id!=conv_pk:
            messages.error(request, f"The chat requesting for change did not match.")
        else:
            chat_instance=chat_form.save()
            messages.success(request, f"edit form with name {chat_instance.title}")
        return redirect("gptutils:get_chat", conv_pk=chat_instance.id)
    return render(request,"htmx_edit_chat_form.html",context={"edit_chat_form":ConversationFormL(instance=chat_instance)})

@login_required
def edit_message(request,message_pk):
    """redirect to edit message form for htmx request return form only
    for the purpose of returning error and large query operations, this page 
    will not be ajax under post request

    Args:
        message_pk: primary key for Message object

    Returns:
        request.POST: redirect to page until the text is fully generated.
        request.GET: return htmx edit message form 
    """
    if request.method == "POST":
        # test for user
        owner_id,message_instance = check_is_creator(request, Message, "edit message", id=message_pk)
        logger.info(f'requested message instance edit form with id {message_pk}')
        if owner_id==None:
            messages.error(request, f"You don't have access to the message")
            return redirect("gptutils:main")
        message_form = MessageForm(request.POST, request.FILES,instance=message_instance)
        if not message_form.is_valid():
            load_form_error_to_messages(request,message_form)    
        elif message_form.instance.id!=message_pk:
            messages.error(request, f"The message requesting for change did not match.")
        else:
            message_instance=message_form.save()
            if message_instance.conversation_id.model==GPTModelChoices.PLAIN:
                add_token(message_instance)
                # delete message after message_instance
                del_message_list=Message.objects.filter(conversation_id=message_instance.conversation_id).filter(created__gt=message_instance.created)
                for i in del_message_list:
                    i.delete()
                messages.success(request, f"Successfully edit the message {message_instance}")
            else:
                add_token(message_instance)
                # delete message after message_instance
                del_message_list=Message.objects.filter(conversation_id=message_instance.conversation_id).filter(created__gt=message_instance.created)
                for i in del_message_list:
                    i.delete()
                # generate response from latest message
                ai_response=generate_message(message_instance.conversation_id)
                if "error" in ai_response:
                    messages.warning(request,f"Error when generating response {ai_response['error']}")
                else:
                    messages.success(request, f"Successfully edit the message {message_instance}")
        return redirect("gptutils:get_chat", conv_pk=message_instance.conversation_id.id)
    # get request:
    # test for user
    owner_id,message_instance = check_is_creator(request, Message, "edit message", id=message_pk)
    if owner_id ==None:
        return render(request,"htmx_edit_message_form.html")
    logger.info(f'requested message instance edit form with id {message_pk}')
    return render(request,"htmx_edit_message_form.html",context={"edit_message_form":MessageForm(instance=message_instance)})

@login_required
@require_POST
def resend_message(request,message_pk):
    """redirect to edit message form for htmx request return form only
    for the purpose of returning error and large query operations, this page will not be ajax under post request
    """
    # test for user
    owner_id,message_instance = check_is_creator(request, Message, "resend message", id=message_pk)
    logger.info(f'requested message instance resend with message id {message_pk}')
    if owner_id==None:
        return redirect("gptutils:main")
    if message_instance.conversation_id.model==GPTModelChoices.PLAIN:
        # delete message after message_instance
        del_message_list=Message.objects.filter(conversation_id=message_instance.conversation_id, created__gt=message_instance.created)
        for i in del_message_list:
            i.delete()
        # generate response from latest message
        messages.success(request, f"Successfully resend the message {message_instance}")
    else:
        # delete message after message_instance
        del_message_list=Message.objects.filter(conversation_id=message_instance.conversation_id,created__gt=message_instance.created)
        for i in del_message_list:
            i.delete()
        # generate response from latest message
        ai_response=generate_message(message_instance.conversation_id)
        if "error" in ai_response:
            messages.warning(request,f"Error when generating response {ai_response['error']}")
        else:
            messages.success(request, f"Successfully resend the message {message_instance}")
    return redirect("gptutils:get_chat", conv_pk=message_instance.conversation_id.id)

@login_required
@require_POST
def delete_message(request, message_pk):
    """only processing post request for deleting message, including message with pk based on time
    for the purpose of returning error and large query operations, this page will not be ajax under post request
    """
    message_instance = get_object_or_404(Message, id=message_pk)
    if message_instance==None:
        messages.error("Message for deletion not found.")
        return redirect("gptutils:main")
    owner_id,conversation_instance = check_is_creator(request, Conversation, pk=message_instance.conversation_id)
    if owner_id==None:
        return redirect("gptutils:main")
    del_message_list=Message.objects.filter(conversation_id=conversation_instance, created__gte=message_instance.created)
    for i in del_message_list:
        i.delete()
    messages.success(request, f"successfully deleted message {message_instance}")
    return redirect("gptutils:get_chat", conv_pk=conversation_instance)

@login_required
def delete_chat(request, conv_pk):
    """delete chat request, only processing post request only, the get request is referring to edit_chat
    for the purpose of returning error and large query operations, this page will not be ajax under post request
    """
    # validate ownership
    owner_id,chat_instance = check_is_creator(request, Conversation, "delete conversation", pk=conv_pk)
    # check permission
    if owner_id==None:
        return redirect("gptutils:main", conv_pk=conv_pk)
    messages.success(request,f"Successfully delete the chat with title {chat_instance.title}")
    chat_instance.delete()
    return redirect("gptutils:main")

def __get_basic_context(request) -> dict:
    """return basic context environment for gptutils module"""
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
