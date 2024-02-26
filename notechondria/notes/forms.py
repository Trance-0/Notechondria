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
from .models import NoteBlock,Note,NoteBlockTypeChoices

class NoteForm(forms.ModelForm):
    """Generate new note form"""

    # Guess what? I am LAZY.
    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (search for 'Meta')
        """

        model = Note
        fields = [
            "title",
            "description"
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

    SUPPORTING_LANGUAGE=(("python", _("Python")),
        ("markdown", _("MarkDown")),
        ("javascript", _("JavaScript")),
    )

    # name of type based widgets
    TYPE_BASED_WIDGETS=["image","file","coding_language_choice"]

    text = forms.CharField(widget=forms.Textarea(attrs={'rows':1}))
    image = forms.ImageField(required=False)
    file = forms.FileField(required=False)
    coding_language_choice=forms.ChoiceField(choices=SUPPORTING_LANGUAGE)
    
    class Meta:
        """Load meta data for multiple field to generate form

        if you are lazy enough, you can also load meta,
        reference: https://docs.djangoproject.com/en/4.2/ref/forms/fields/
        (search for 'Meta')
        """
        model = NoteBlock
        fields = [
            # block type should render differently by ajax
            "block_type",
            "image",
            "file",
            "coding_language_choice",
        ]

    def __init__(self, *args, **kwargs):
        """add extra arguments for each input,
        reference: https://stackoverflow.com/questions/29716023/add-class-to-form-field-django-modelform
        """
        super(NoteBlockForm, self).__init__(*args, **kwargs)
        for visible in self.visible_fields():
            visible.field.widget.attrs["class"] = "form-control"
        self.fields['text'].widget.attrs['rows'] = 6
        self.fields['text'].widget.attrs["class"] += " w-100"
        # add class to type based widgets
        for widget_name in self.TYPE_BASED_WIDGETS:
            self.fields[widget_name].widget.attrs["class"]+=" type-based-widgets"
        if self.instance.pk!=None:
            # load default variable based on block type
            if self.instance.block_type== NoteBlockTypeChoices.CODE:
                self.fields['coding_language_choice'].initial = self.instance.args