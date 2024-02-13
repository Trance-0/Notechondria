import base64
import logging
from django.db import models
from django.utils.timezone import now
from creators.models import Creator
from django.utils.translation import gettext_lazy as _

logger = logging.getLogger("django")

# Create your models here.
class GPTModelChoices(models.TextChoices):
    """User group choices, may be more efficient if use django internal group"""

    # gpt4-v
    GPT4_V = "gpt-4-vision-preview", _("GPT 4 Vision with auto resolution")
    GPT4_VH = "gpt-4-vision-preview:high", _("GPT 4 Vision with high resolution")
    GPT4_VL = "gpt-4-vision-preview:low", _("GPT 4 Vision with low resolution")
    # gpt4-chat
    GPT4_1106 = "gpt-4-1106-preview", _("GPT 4 Nov preview")
    GPT4_32K = "gpt-4-32k", _("GPT 4 32K model")
    # gpt3-chat
    GPT3_1106 = "gpt-3.5-turbo-1106", _("GPT 3.5 Nov preview")
    GPT3_16K = "gpt-3.5-turbo-16k", _("GPT 3.5 16K model")
    GPT3_T = "gpt-3.5-turbo", _("GPT 3 turbo model")
    # plain-chat room
    PLAIN = "plain-chat", _("Plain chat room for testing")
    # tts
    # TTS_1 = "tts-1", _("TTS 1 text to speech model")
    # TTS_1_HD = "tts-1-hd", _("TTS 1 text to speech model with high resolution")
    # whisper (open source)
    # WHISPER = "whisper", _("Normal")


class Conversation(models.Model):
    """for django built-in authentication: https://docs.djangoproject.com/en/4.2/ref/contrib/auth/"""

    # This objects contains the username, password, first_name, last_name, and email of member.
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleteted, wheather the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    # plan for chat room in near future
    param = models.CharField(max_length=255,null=True)
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
    temperature = models.DecimalField(default=0.9, max_length=3, max_digits=2, decimal_places=2, null=False)
    memory_size = models.IntegerField(default=3, null=False)
    # The maximum number of tokens to generate in the chat completion.
    max_tokens = models.IntegerField(default=500, null=False)
    timeout = models.IntegerField(default=600, null=False)
    # Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency
    # in the text so far, decreasing the model's likelihood to repeat the same line verbatim.
    frequency_penalty = models.DecimalField(default=0.9, max_length=3, max_digits=2, decimal_places=2, null=False)
    # Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear
    # in the text so far, increasing the model's likelihood to talk about new topics.
    presence_penalty = models.DecimalField(default=0.9, max_length=3, max_digits=2, decimal_places=2, null=False)

    total_prompt_tokens=models.IntegerField(default=0, null=False)
    total_completion_tokens=models.IntegerField(default=0, null=False)

    def __str__(self):
        """for better list display"""
        return f"{self.title}: {self.model}"
    
    def is_visual_model(self):
        return (self.model == GPTModelChoices.GPT4_V or 
                                    self.model == GPTModelChoices.GPT4_VH or
                                    self.model == GPTModelChoices.GPT4_VL)
    
    # the following function cannot be created here due to reference recursion
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
    image = models.ImageField(upload_to="message_pic",blank=True, null=True)
    # file field is currently unsupported
    file = models.FileField(upload_to="message_file",blank=True, null=True)
    file_id = models.CharField(max_length=255, blank=True, null=True)
    # unlimited size for PostgreSQL, the max_length value have to be set for other databases.
    text = models.TextField(blank=True, null=True)

    def __str__(self) -> str:
        return f'{self.text[:min(len(self.text),50)]}: {self.created}'

    def to_dict(self):
        def encode_image(image_path):
            """Function to encode the image"""
            with open(image_path, "rb") as image_file:
                return base64.b64encode(image_file.read()).decode("utf-8")
            
        message={
                "role": self.role,
                "content": [
                    ]}
        if self.text:
            message["content"].append({"type": "text", "text": self.text})
        # skip image processing when model is not visual one.
        if self.image and self.conversation_id.is_visual_model():
            base64_image = encode_image(self.image.path)
            logger.debug(base64_image)
            image_ext=self.image.path.split(".")[-1]
            message["content"].append({"type": "image_url",
                        "image_url": {"url": f"data:image/{image_ext};base64,{base64_image}"},"detail": "auto" if len(self.conversation_id.model.split(":"))==1 else self.conversation_id.model.split(":")[1] })
        # if self.file:
        return message