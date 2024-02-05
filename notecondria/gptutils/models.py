import random
from django.db import models
from django.utils.timezone import now
from creators.models import Creator
from django.utils.translation import gettext_lazy as _


# Create your models here.
class GPTModelChoices(models.TextChoices):
    """User group choices, may be more efficient if use django internal group"""

    # gpt4-v
    GPT4_V = "gpt-4-vision-preview", _("GPT 4 Vision")
    # gpt4-chat
    GPT4_1106 = "gpt-4-1106-preview", _("GPT 4 Nov preview")
    GPT4_32K = "gpt-4-32k", _("GPT 4 32K model")
    # gpt3-chat
    GPT3_1106 = "gpt-3.5-turbo-1106", _("GPT 3.5 Nov preview")
    GPT3_16K = "gpt-3.5-turbo-16k", _("GPT 3.5 16K model")
    GPT3_T = "gpt-3.5-turbo", _("GPT 3 turbo model")
    # tts
    TTS_1 = "tts-1", _("Normal")
    TTS_1_HD = "tts-1-hd", _("Normal")
    # whisper (open source)
    WHISPER = "whisper", _("Normal")


class Conversation(models.Model):
    """for django built-in authentication: https://docs.djangoproject.com/en/4.2/ref/contrib/auth/"""

    # This objects contains the username, password, first_name, last_name, and email of member.
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleteted, wheather the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    sharing_id = models.CharField(max_length=36,unique=True,null=False)
    title = models.CharField(max_length=100, null=True)

    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    last_use=models.DateTimeField(auto_now=True,null=False)

    # model setting parameter
    # reference:https://platform.openai.com/docs/api-reference/chat/create
    model = models.CharField(
        null=False,
        max_length=32,
        choices=GPTModelChoices.choices,
        default=GPTModelChoices.GPT4_1106,
    )
    # [0,1] the larger the more uncertain
    temperature = (
        models.DecimalField(default=0.9, max_length=3, max_digits=2, null=False),
    )
    memory_size = models.IntegerField(default=3, null=False)
    # The maximum number of tokens to generate in the chat completion.
    max_token = models.IntegerField(default=500, null=False)
    timeout = models.IntegerField(default=600, null=False)
    # Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency
    # in the text so far, decreasing the model's likelihood to repeat the same line verbatim.
    frequency_penalty = (
        models.DecimalField(default=0.9, max_length=3, max_digits=2, null=False),
    )
    # Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear
    # in the text so far, increasing the model's likelihood to talk about new topics.
    presence_penalty = (
        models.DecimalField(default=0.9, max_length=3, max_digits=2, null=False),
    )

    def __str__(self):
        """for better list display"""
        return f"{self.title} created by {self.creator_id.user_id.username}"
    
    # def created(self)->datetime:
    #     MessageRoleChoices.objects.filter().orderby()

    # def last_change(self):
    #     MessageRoleChoices.objects.filter().orderby()

class MessageRoleChoices(models.TextChoices):
    """Message role choices
    Used to generate requests
    May be more efficient if use django internal group
    """

    SYSTEM = "system", _("Default prompt")
    USER = "user", _("User message")
    ASSISTANT = "assistant", _("Model message")


class Message(models.Model):
    """Message model for each user"""

    conversation_id = models.ForeignKey(
        Conversation, on_delete=models.CASCADE, null=False
    )
    # for created, create one time value to timezone.now()
    created = models.DateTimeField(auto_now_add=True,null=False)
    role = models.CharField(
        null=False,
        max_length=9,
        choices=MessageRoleChoices.choices,
        default=MessageRoleChoices.USER,
    )
    image = models.ImageField(upload_to="message_pic", null=True)
    file = models.FileField(upload_to="message_file", null=True)
    text = models.CharField(max_length=2048, null=True)

