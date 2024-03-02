"""
Escape from forms

With django built-in validation and everything else!
https://docs.djangoproject.com/en/4.2/topics/forms/
"""
from PIL import Image
from django import forms
from django.utils.translation import gettext_lazy as _
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.contrib.auth.models import User
from .models import Conversation, Message


class ResizedImageValidator:
    """validate if the user have cropped the image correctly"""

    def __init__(self, x: int, y: int, width: int, height: int):
        self.x = x
        self.y = y
        self.width = width
        self.height = height

    def validate(self, image: Image, user=None):
        """Validate by inputting the cropping image, raise error if size mismatched"""
        w, h = image.size
        if w < self.x + self.width or h < self.y + self.height:
            raise ValidationError(
                _(
                    "The image size did not match with cropping parameters with expected width %(ew)d, height %(eh)d but actual data recieved is %(w)d, %(h)d"
                ),
                params={
                    "ew": self.x + self.width,
                    "eh": self.y + self.height,
                    "w": w,
                    "h": h,
                },
            )

    def clean(self, image: Image, resize=(200, 200)) -> Image:
        """return cleaned image"""
        cropped_image = image.crop(
            (self.x, self.y, self.width + self.x, self.height + self.y)
        )
        return cropped_image.resize(resize, Image.ANTIALIAS)

    def get_help_text(self):
        """return standard help_text"""
        return _("Please try to re-cropping the image or contact admin for bug report")


class ConversationFormS(forms.ModelForm):
    """Generate gpt chat with parameters"""

    # add form_type identifier for model creation
    form_type=forms.CharField(widget=forms.HiddenInput(),required=True)
    title=forms.CharField(help_text="Name of the conversation",max_length=100,required=True)
    
    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (search for 'Meta')
        """

        model = Conversation
        fields = ["form_type",
                  "title",
                    "model"]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(ConversationFormS, self).__init__(*args, **kwargs)
        self.fields["form_type"].initial = "simple"
        for visible in self.visible_fields():
            visible.field.widget.attrs["class"] = "form-control"

class ConversationFormL(forms.ModelForm):
    """Generate gpt chat with parameters"""

    # add form_type identifier for model creation
    form_type=forms.CharField(widget=forms.HiddenInput(),required=True)
    title=forms.CharField(help_text="Name of the conversation",max_length=100,required=True)
    temperature=forms.FloatField(help_text="What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic.",validators=[
            MaxValueValidator(2),
            MinValueValidator(0)
        ])
    memory_size=forms.IntegerField(help_text="Number of message to included during the conversation, the larger then value, the longer can GPT recall your message, but this comes with higher token costs.",validators=[MinValueValidator(0)])
    max_tokens=forms.IntegerField(help_text="The maximum number of tokens that can be generated in the chat completion.",validators=[MinValueValidator(100)])
    timeout=forms.IntegerField(help_text="Override the client-level default timeout for this request, in seconds",validators=[MinValueValidator(5)])
    frequency_penalty=forms.FloatField(help_text="Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.",validators=[
            MaxValueValidator(2),
            MinValueValidator(-2)
        ])
    presence_penalty=forms.FloatField(help_text="Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.",validators=[
            MaxValueValidator(2),
            MinValueValidator(-2)
        ])
    system_prompt=forms.CharField(help_text="The message that attached at the head of message file for each request you send to openAI, this prompt will be send for each message, so you'd better to keep it short, or leave it blank if you want",widget=forms.Textarea(attrs={'rows':3}),required=False)

    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (search for 'Meta')
        """

        model = Conversation
        fields = ["form_type",
                  "title",
                    "model",
                   "temperature",
                   "memory_size",
                   "max_tokens",
                   "timeout",
                   "frequency_penalty",
                   "presence_penalty",
                   "system_prompt"]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(ConversationFormL, self).__init__(*args, **kwargs)
        self.fields["form_type"].initial = "advanced"
        for visible in self.visible_fields():
            visible.field.widget.attrs["class"] = "form-control"


def validate_user_name(new_user_name, user=None) -> None:
    """test if username repeated based on server data"""
    if user is not None and user.user_id.username == new_user_name:
        return
    if User.objects.filter(username=new_user_name).exists():
        raise ValidationError(
            _("User name already exists %(server_user_name)s"),
            params={"server_user_name": new_user_name},
        )

class MessageForm(forms.ModelForm):
    """Generate new message form"""

    text = forms.CharField(widget=forms.Textarea(attrs={'rows':1}))
    image = forms.ImageField(required=False)
    # Guess what? I am LAZY.
    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (serach for 'Meta')
        """

        model = Message
        fields = [
            # "conversation_id",
            # "role",
            "text",
            "image",
        ]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(MessageForm, self).__init__(*args, **kwargs)
        for visible in self.visible_fields():
            visible.field.widget.attrs["class"] = "form-control"
        if self.instance.pk!=None:
            self.fields['text'].widget.attrs['rows'] = 6
            self.fields['text'].widget.attrs["class"] = "form-control w-100"