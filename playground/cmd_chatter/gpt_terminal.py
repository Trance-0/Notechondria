"""cmd chatter for fun!, use api for gpt access."""
import base64
import os
from pathlib import Path
from openai import OpenAI
import requests

from dotenv import load_dotenv

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent

load_dotenv(os.path.join(BASE_DIR,'.env'))

client=OpenAI(api_key=os.environ("OPENAI_KEY"))
# create chat hist
hist=[]
hist_size=int(os.environ("MESSAGE_SIZE","1"))
model_name=os.environ("MODEL_NAME","gpt-4o-mini")

def generate_message():
    """ Void function that generate the AI response given the conversation
    This function is the raw version of request that will fit any api.
    """
    def encode_image(image_path):
        """Function to encode the image"""
        with open(image_path, "rb") as image_file:
            return base64.b64encode(image_file.read()).decode("utf-8")
    payload=[]
    try:
        stream = client.chat.completions.create(
            messages=payload,
            model=model_name,
            temperature=float(os.environ("TEMPERATURE","0.2")),
            max_tokens=os.environ("MAX_TOKENS","1000"),
            presence_penalty=float(conversation.presence_penalty),
            frequency_penalty=float(conversation.frequency_penalty),
            stream=True,
        )
        response=[]
        for chunk in stream:
            if chunk.choices[0].delta.content is not None:
                response.append(chunk.choices[0].delta.content)
                yield html.escape(chunk.choices[0].delta.content).replace('\n','<br>')
        dummy_message.text="".join(response)
        # token calculation (approximate)
        conversation.total_completion_tokens += 3  # every reply is primed with <|start|>assistant<|message|>
        add_token(dummy_message)
        logger.info(u"{}: get streaming message as below: \n {}".format(conversation.creator_id,__short_text(dummy_message.text)))
        # save dummy message
        dummy_message.save()
        logger.info(u"dummy message saved with following text: {}".format(__short_text(dummy_message.text)))
        for message in messages_list:
            add_token(message)
    except Exception as e:
        logger.error(e)