import random
from django.db import models
from django.contrib import messages
from django.forms import ModelForm

def get_object_or_None(Model:models,**kwargs):
    """Utils to get modal or return None if no such object is found

    Args:
      Model: the modal to search in, must be django.models.Model
      **kwargs: conditions to search for the model objects, same format as django.db.model.objects.get() function inputs

    Returns:
      None if no such object exists or the object found
    """
    try:
        res= Model.objects.get(**kwargs)
    except:
        res=None
    return res

def generate_unique_id(Model:models,field:str,length:int=8) -> str:
    """Generate unique id for a django model with given condition

    Attribute:
        characters: the character set of random choices, default is Base64 strings.

    Args:
        field: field name of the unique id that you want to generate.
        length: default generate code with length 8, this value should be greater than 1.

    Returns:
        random string with give size

    """
    characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-"
    n = len(characters)
    res = ""
    for _ in range(length):
        res += characters[random.randint(0, n - 1)]
    filters = {field:res}
    while Model.objects.filter(**filters).exists():
        res = ""
        for _ in range(length):
            res += characters[random.randint(0, n - 1)]
        filters = {field:res}
    return res

def load_form_error_to_messages(request,form:ModelForm):
    """Load error message in form to django.contrib.messages

    Args:
        request: http request
        form: form with errors

    """
    for key, value in form.errors.items():
        messages.error(request, f"Validation error on field {key}:{[error for error in value]}")
 