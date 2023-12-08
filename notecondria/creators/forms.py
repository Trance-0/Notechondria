"""
Escape from forms

With django built-in validation and everything else!
https://docs.djangoproject.com/en/4.2/topics/forms/
"""
from typing import Any
from PIL import Image
from django import forms
from django.utils.translation import gettext_lazy as _
from django.contrib.auth.validators import UnicodeUsernameValidator
from django.contrib.auth.password_validation import (
    validate_password,
    get_default_password_validators,
)
from django.core.exceptions import ValidationError
from django.contrib.auth.models import User
from django.core.validators import EmailValidator
from .models import Creator


class RepassValidator:
    """validate if the user enter the password correctly"""

    def __init__(self, repassword: str):
        self.repass = repassword

    def validate(self, password,user=None):
        """default validate function"""
        if not password == self.repass:
            raise ValidationError(
                _("This password did not match with your re-entered password.")
            )

    def get_help_text(self):
        """return standard help_text"""
        return _("Your password must match with the re-entered password.")


class ResizedImageValidator:
    """validate if the user have cropped the image correctly"""

    def __init__(self, x: int, y: int, width: int, height: int):
        self.x = x
        self.y = y
        self.width = width
        self.height = height

    def validate(self, image: Image,user=None):
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
        """return cleanned image """
        cropped_image = image.crop(
            (self.x, self.y, self.width + self.x, self.height + self.y)
        )
        return cropped_image.resize(resize, Image.ANTIALIAS)

    def get_help_text(self):
        """return standard help_text"""
        return _("Please try to re-cropping the image or contact admin for bug report")


class LoginForm(forms.Form):
    """Generate login form based on Creator model."""

    username = forms.CharField(
        label="Username",
        validators=[UnicodeUsernameValidator],
        max_length=150,
        required=True,
    )
    password = forms.CharField(
        label="Password", widget=forms.PasswordInput, required=True
    )

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(LoginForm, self).__init__(*args, **kwargs)
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


class RegisterForm(forms.ModelForm):
    """Generate register form based on Creator model."""

    # Guess what? I am LAZY.
    user_name = forms.CharField(
        max_length=150, validators=[UnicodeUsernameValidator], required=True
    )
    image = forms.ImageField(
        help_text="To reduce request count, please upload image after you completed all other forms to reduce error rates",
        required=False,
    )
    first_name = forms.CharField(max_length=150, required=True)
    last_name = forms.CharField(max_length=150, required=True)
    email = forms.CharField(max_length=255, validators=[EmailValidator], required=True)
    password = forms.CharField(widget=forms.PasswordInput, required=True)
    repassword = forms.CharField(
        label="Re-enter your password", widget=forms.PasswordInput, required=True
    )

    # attributes for image cropping
    x = forms.FloatField(widget=forms.HiddenInput())
    y = forms.FloatField(widget=forms.HiddenInput())
    width = forms.FloatField(widget=forms.HiddenInput())
    height = forms.FloatField(widget=forms.HiddenInput())

    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (serach for 'Meta')
        """

        model = Creator
        fields = [
            "image",
            "x",
            "y",
            "width",
            "height",
            "user_name",
            "first_name",
            "last_name",
            "email",
            "password",
            "repassword",
            "motto",
            "social_link",
        ]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(RegisterForm, self).__init__(*args, **kwargs)
        self.fields["social_link"].required = False
        self.fields["motto"].required = False
        for visible in self.visible_fields():
            visible.field.widget.attrs["class"] = "form-control"
        # prefill instance value
        if self.instance.pk:
            self.fields["user_name"].initial = self.instance.user_id.username
            self.fields["image"].initial = self.instance.image
            self.fields["x"].initial = self.instance.x
            self.fields["y"].initial = self.instance.y
            self.fields["width"].initial = self.instance.width
            self.fields["height"].initial = self.instance.height
            self.fields["first_name"].initial = self.instance.user_id.first_name
            self.fields["last_name"].initial = self.instance.user_id.last_name
            self.fields["email"].initial = self.instance.user_id.email
            self.fields["password"].required = False
            self.fields["repassword"].required = False

    # custom validation
    def clean(self):
        """custom validation for repassword and forbid user registration attack

        check default errors
        check user name repeated
        check if user exist
        validate password
        """
        # check default errors
        if any(self.errors):
            return
        data = self.cleaned_data
        # validate password
        repass = RepassValidator(data["repassword"])
        validators = get_default_password_validators()
        validators.append(repass)
        validate_password(data["password"], password_validators=validators)
        # check if user exist
        validate_user_name(data["user_name"])

    def save(self, commit: bool = ...) -> Creator:
        creator_instance = super(RegisterForm, self).save(commit=False)
        # create user
        user = User.objects.create(
            username=self.cleaned_data["user_name"],
            first_name=self.cleaned_data["first_name"],
            last_name=self.cleaned_data["last_name"],
            email=self.cleaned_data["email"],
        )
        user.set_password(self.cleaned_data["password"])
        # the user will not be save automatically
        user.save()
        creator_instance.user_id = user
        # load image
        img_validator = ResizedImageValidator(
            self.cleaned_data.get("x"),
            self.cleaned_data.get("y"),
            self.cleaned_data.get("width"),
            self.cleaned_data.get("height"),
        )
        # resize image based on parameters
        img_validator.validate(Image.open(creator_instance.image))
        creator_instance.image=img_validator.clean(Image.open(creator_instance.image))

        # the creator will not be saved automatically due to false commit
        return creator_instance.save()


class EditForm(forms.ModelForm):
    """Generate register form based on Creator model."""

    # Guess what? I am LAZY.
    user_name = forms.CharField(
        max_length=150, validators=[UnicodeUsernameValidator], required=False
    )
    # reset id attribute
    new_image = forms.ImageField(
        widget=forms.ClearableFileInput(attrs={"id": "id_image"}),
        help_text="To reduce request count, please upload image after you completed all other forms to reduce error rates",
        required=False,
    )
    first_name = forms.CharField(max_length=150, required=False)
    last_name = forms.CharField(max_length=150, required=False)
    email = forms.CharField(max_length=255, validators=[EmailValidator], required=False)
    password = forms.CharField(widget=forms.PasswordInput, required=False)
    repassword = forms.CharField(
        label="Re-enter your password", widget=forms.PasswordInput, required=False
    )

    # attributes for image cropping
    x = forms.FloatField(widget=forms.HiddenInput())
    y = forms.FloatField(widget=forms.HiddenInput())
    width = forms.FloatField(widget=forms.HiddenInput())
    height = forms.FloatField(widget=forms.HiddenInput())

    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (serach for 'Meta')
        """

        model = Creator
        fields = [
            "new_image",
            "x",
            "y",
            "width",
            "height",
            "user_name",
            "first_name",
            "last_name",
            "email",
            "password",
            "repassword",
            "motto",
            "social_link",
        ]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(EditForm, self).__init__(*args, **kwargs)
        self.fields["social_link"].required = False
        self.fields["motto"].required = False
        for visible in self.visible_fields():
            visible.field.widget.attrs["class"] = "form-control"
        # prefill instance value from saved changes
        if self.instance.pk:
            self.fields["user_name"].initial = self.instance.user_id.username
            # self.fields["image"].initial = self.instance.image
            self.fields["first_name"].initial = self.instance.user_id.first_name
            self.fields["last_name"].initial = self.instance.user_id.last_name
            self.fields["email"].initial = self.instance.user_id.email
            self.fields["password"].required = False
            self.fields["repassword"].required = False

    # custom validation
    def clean(self):
        """custom validation for repassword and forbid user registration attack

        check default errors
        check user name repeated
        check if user exist
        validate password
        """
        # check default errors
        if any(self.errors):
            return
        data = self.cleaned_data
        # validate password
        if data["password"] != "":
            repass = RepassValidator(data["repassword"])
            validators = get_default_password_validators()
            validators.append(repass)
            validate_password(data["password"], password_validators=validators)
        # check user name repeated
        validate_user_name(data["user_name"])

    def save(self, commit: bool = ...) -> Creator:
        creator_instance = super(EditForm, self).save(commit=False)
        user_instance = creator_instance.user_id
        password = self.cleaned_data["password"]
        # skip empty fields for saving user instance
        if self.cleaned_data["user_name"] != "":
            user_instance.username = self.cleaned_data["user_name"]
        # django generic class function, password validation in form module
        if password != "":
            user_instance.set_password(password)
        if self.cleaned_data["first_name"] != "":
            user_instance.firstname = self.cleaned_data["first_name"]
        if self.cleaned_data["last_name"] != "":
            user_instance.lastname = self.cleaned_data["last_name"]
        if self.cleaned_data["email"] != "":
            user_instance.email = self.cleaned_data["email"]
        # the user will not be save automatically
        user_instance.save()
        # skip empty fields for saving creator instance

        # load image
        x = self.cleaned_data.get("x")
        y = self.cleaned_data.get("y")
        w = self.cleaned_data.get("width")
        h = self.cleaned_data.get("height")
        # resize image based on parameters
        image = Image.open(creator_instance.image)
        cropped_image = image.crop((x, y, w + x, h + y))
        resized_image = cropped_image.resize((200, 200), Image.ANTIALIAS)
        resized_image.save(creator_instance.image.path)

        creator_instance.image = resized_image

        if commit:
            creator_instance.save()
        return creator_instance
