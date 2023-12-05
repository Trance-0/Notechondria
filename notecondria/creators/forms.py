"""
Escape from forms

With django built-in validation and everything else!
https://docs.djangoproject.com/en/4.2/topics/forms/
"""
from django import forms
from django.utils.translation import gettext_lazy as _
from django.contrib.auth.validators import UnicodeUsernameValidator
from django.core.exceptions import ValidationError
from django.contrib.auth.models import User
from django.core.validators import EmailValidator
from .models import Creator


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

class RegisterForm(forms.ModelForm):
    """Generate register form based on Creator model."""

    # Guess what? I am LAZY.
    user_name = forms.CharField(
        max_length=150, validators=[UnicodeUsernameValidator], required=True
    )
    first_name = forms.CharField(max_length=150, required=True)
    last_name = forms.CharField(max_length=150, required=True)
    email = forms.CharField(max_length=255, validators=[EmailValidator])
    password = forms.CharField(
        widget=forms.PasswordInput,
        help_text="We do have validator if I have enough time.",
        required=True,
    )
    repassword = forms.CharField(
        label="Re-enter your password", widget=forms.PasswordInput, required=True
    )

    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (serach for 'Meta')
        """

        model = Creator
        fields = [
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
        # check user name repeated
        # check if user exist
        if User.objects.filter(username=data["user_name"]).exists() and (
            self.instance.pk is None
            or self.instance.user_id.username != data["user_name"]
        ):
            raise ValidationError(_("User already exists"))
            # test password match
        if self.instance.pk is not None and data["password"] == "":
            return
        # password validation:
        if len(data["password"]) < 8:
            raise ValidationError(_("Password is too short"))
        if data["repassword"] != data["password"]:
            raise ValidationError(_("Re-entered passoword mismatch"))
        # check password match
