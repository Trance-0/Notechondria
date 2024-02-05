"""
Escape from forms

With django built-in validation and everything else!
https://docs.djangoproject.com/en/4.2/topics/forms/
"""
from PIL import Image
from django import forms
from django.utils.translation import gettext_lazy as _
from django.core.exceptions import ValidationError
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
        """return cleanned image"""
        cropped_image = image.crop(
            (self.x, self.y, self.width + self.x, self.height + self.y)
        )
        return cropped_image.resize(resize, Image.ANTIALIAS)

    def get_help_text(self):
        """return standard help_text"""
        return _("Please try to re-cropping the image or contact admin for bug report")


class ConversationForm(forms.Form):
    """Generate gpt chat with parameters"""

    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (serach for 'Meta')
        """

        model = Conversation
        fields = [
            "model",
            "temperature",
        ]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(ConversationForm, self).__init__(*args, **kwargs)
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

    # Guess what? I am LAZY.
    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (serach for 'Meta')
        """

        model = Message
        fields = [
            "conversation_id",
            "role",
            "image",
            "text",
        ]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(ConversationForm, self).__init__(*args, **kwargs)
        for visible in self.visible_fields():
            visible.field.widget.attrs["class"] = "form-control"