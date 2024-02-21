""" a module responsible for sending backend request to openAI

"""

import os
import logging
import tiktoken
import json
from openai import OpenAI
from PIL import Image

logger = logging.getLogger("django")

from .models import Conversation,Message,MessageRoleChoices,GPTModelChoices

# OpenAI API Key
api_key = os.getenv("OPENAI_API_KEY")

client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

def generate_message(conversation:Conversation):
    """ Generate function as the user designed in conversation"""
    messages_list=Message.objects.filter(conversation_id=conversation).order_by("-created")[:conversation.memory_size]
    model_name=conversation.model.split(':')[0]
    payload=[i.to_dict() for i in messages_list]
    # Convert Python to JSON for printing
    message_string='\n'.join([json.dumps(i.to_dict()) for i in messages_list])
    logger.debug(conversation.creator_id,f"sent message as below: \n {message_string}")
    response=None
    try:
        response = client.chat.completions.create(
            messages=payload,
            model=model_name,
            temperature=float(conversation.temperature),
            max_tokens=conversation.max_tokens,
            presence_penalty=float(conversation.presence_penalty),
            frequency_penalty=float(conversation.frequency_penalty),
            timeout=conversation.timeout
        )
    except Exception as e:
        response={"error":e}
    logger.debug(response)
    # generate response msg to conversation
    if not "error" in response:
        # update token count (precise)
        conversation.total_prompt_tokens+=response.usage.prompt_tokens
        conversation.total_completion_tokens+=response.usage.completion_tokens
        conversation.save()
        response_choices=response.choices
        Message.objects.create(conversation_id=conversation,role=MessageRoleChoices.ASSISTANT,text=response_choices[0].message.content)
    return response

def generate_stream_message(conversation:Conversation):
    """generate stream message needs to have a dummy message for AI input, the AI message will store in the dummy message"""
    global client

    messages_list=Message.objects.filter(conversation_id=conversation).order_by("-created")[:conversation.memory_size+1]
    dummy_message=messages_list[0]
    model_name=conversation.model.split(':')[0]
    payload=[i.to_dict() for i in messages_list[1:]]
    response=None
    try:
        stream = client.chat.completions.create(
            messages=payload,
            model=model_name,
            temperature=float(conversation.temperature),
            max_tokens=conversation.max_tokens,
            presence_penalty=float(conversation.presence_penalty),
            frequency_penalty=float(conversation.frequency_penalty),
            stream=True,
        )
        response=[]
        for chunk in stream:
            if chunk.choices[0].delta.content is not None:
                response.append(chunk.choices[0].delta.content)
                yield chunk.choices[0].delta.content
        dummy_message.text="".join(response)
        # token calculation (approximate)
        conversation.total_completion_tokens += 3  # every reply is primed with <|start|>assistant<|message|>
        add_token(dummy_message)
        for message in messages_list:
            add_token(message)
    except Exception as e:
        logger.error(e)

def add_token(message:Message):
    conversation_instance=message.conversation_id
    if message.role==MessageRoleChoices.ASSISTANT:
        conversation_instance.total_completion_tokens+=__num_tokens_from_text(message.text)
    else:
        if message.image and message.conversation_id.is_visual_model():
            im = Image.open(message.image)
            width, height = im.size
            # image token reference from: https://openai.com/pricing
            conversation_instance.total_prompt_tokens+=85+((width+511)//512*(height+511)//512)*170
        conversation_instance.total_prompt_tokens+=__num_tokens_from_text(message.text)

def __num_tokens_from_text(text:str, model="gpt-3.5-turbo-0613"):
    """Return the number of tokens used by a list of messages.
        reference: https://github.com/openai/openai-cookbook/blob/main/examples/How_to_count_tokens_with_tiktoken.ipynb
    """
    try:
        encoding = tiktoken.encoding_for_model(model)
    except KeyError:
        logger.warning("Warning: model not found. Using cl100k_base encoding.")
        encoding = tiktoken.get_encoding("cl100k_base")
    if model in {
        "gpt-3.5-turbo-0613",
        "gpt-3.5-turbo-16k-0613",
        "gpt-4-0314",
        "gpt-4-32k-0314",
        "gpt-4-0613",
        "gpt-4-32k-0613",
        }:
        tokens_per_message = 3
        tokens_per_name = 1
    elif model == "gpt-3.5-turbo-0301":
        tokens_per_message = 4  # every message follows <|start|>{role/name}\n{content}<|end|>\n
        tokens_per_name = -1  # if there's a name, the role is omitted
    elif "gpt-3.5-turbo" in model:
        logger.warning("Warning: gpt-3.5-turbo may update over time. Returning num tokens assuming gpt-3.5-turbo-0613.")
        return __num_tokens_from_text(text, model="gpt-3.5-turbo-0613")
    elif "gpt-4" in model:
        logger.warning("Warning: gpt-4 may update over time. Returning num tokens assuming gpt-4-0613.")
        return __num_tokens_from_text(text, model="gpt-4-0613")
    else:
        raise NotImplementedError(
            f"""num_tokens_from_messages() is not implemented for model {model}. See https://github.com/openai/openai-python/blob/main/chatml.md for information on how messages are converted to tokens."""
        )
    return tokens_per_message+len(encoding.encode(text))

# def generate_message_raw(conversation:Conversation):
#     """ Void function that generate the AI response given the conversation
#     This function is the raw version of request that will fit any api.
#     """
#     import base64
#     import requests
#     def encode_image(image_path):
#         """Function to encode the image"""
#         with open(image_path, "rb") as image_file:
#             return base64.b64encode(image_file.read()).decode("utf-8")
#     headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}
#     message_list=Message.objects.filter(conversation_id=conversation).order_by("-created")[:conversation.memory_size]
#     payload = {
#         "model": "gpt-4-vision-preview",
#         "messages": [
#             i.to_dict() for i in message_list
#         ],
#         "max_tokens": conversation.max_token,
#     }
#     response = requests.post(
#         "https://api.openai.com/v1/chat/completions",
#         headers=headers,
#         json=payload,
#     )
#     logger.debug(payload)
#     logger.debug(response.json())
#     json_res = response.json()
#     # generate response msg to conversation
#     if not "error" in response:
#         # update token count
#         conversation.total_prompt_tokens+=json_res["usage"]["prompt_tokens"]
#         conversation.total_completion_tokens+=json_res["usage"]["completion_tokens"]
#         conversation.save()
#         response_choices=json_res["choices"]
#         Message.objects.create(conversation_id=conversation,role=MessageRoleChoices.ASSISTANT,text=response_choices[0]["message"]["content"])
#     return json_res
