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
from .models import NoteBlock,Note

class NoteForm(forms.ModelForm):
    """Generate new note form"""

    text = forms.CharField(widget=forms.Textarea(attrs={'rows':1}))
    # Guess what? I am LAZY.
    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (serach for 'Meta')
        """

        model = Note
        fields = [
            "title",
        ]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(NoteForm, self).__init__(*args, **kwargs)
        for visible in self.visible_fields():
            visible.field.widget.attrs["class"] = "form-control"

class NoteBlockForm(forms.ModelForm):
    """Generate note block form"""

    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (serach for 'Meta')
        """
        model = NoteBlock
        # fields = [
        #     "",
        # ]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(NoteForm, self).__init__(*args, **kwargs)
        for visible in self.visible_fields():
            visible.field.widget.attrs["class"] = "form-control"
