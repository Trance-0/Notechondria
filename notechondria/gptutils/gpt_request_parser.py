""" a module responsible for sending backend request to openAI

"""

import os
import base64
import requests
import logging

logger = logging.getLogger("django")

from .models import Conversation,Message,MessageRoleChoices

# OpenAI API Key
api_key = os.getenv("OPENAI_API_KEY")


def encode_image(image_path):
    """Function to encode the image"""
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")


def gpt4v_request(image_path: str, prompt: str, max_tokens: int = 300):
    """processing requests send to gpt3-v
    reference: https://platform.openai.com/docs/guides/vision
    """
    # Getting the base64 string
    base64_image = encode_image(image_path)

    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}

    payload = {
        "model": "gpt-4-vision-preview",
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{base64_image}"},
                    },
                ],
            }
        ],
        "max_tokens": max_tokens,
    }

    response = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers=headers,
        json=payload,
    )

    return response.json()

def generate_message(conversation:Conversation):
    """ Void function that generate the AI response given the conversation
    """

    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}

    message_list=Message.objects.filter(conversation_id=conversation).order_by("-created")[:conversation.memory_size]
    payload = {
        "model": "gpt-4-vision-preview",
        "messages": [
            i.to_json() for i in message_list
        ],
        "max_tokens": conversation.max_token,
    }

    response = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers=headers,
        json=payload,
    )

    logger.debug(payload)
    logger.debug(response.json())

    json_res = response.json()

    # generate response msg to conversation
    if not "error" in response:
        # update token count
        conversation.total_prompt_tokens+=json_res["usage"]["prompt_tokens"]
        conversation.total_completion_tokens+=json_res["usage"]["completion_tokens"]
        conversation.save()
        response_choices=json_res["choices"]
        Message.objects.create(conversation_id=conversation,role=MessageRoleChoices.ASSISTANT,text=response_choices[0]["message"]["content"])

    return json_res