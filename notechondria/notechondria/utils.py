import random
from django.db import models
from django.contrib import messages
from django.forms import ModelForm
from creators.models import Creator

def get_object_or_None(model:models.Model,**kwargs):
    """Utils to get modal or return None if no such object is found

    Args:
      model: the modal to search in, must be django.models.Model
      **kwargs: conditions to search for the model objects, same format as django.db.model.objects.get() function inputs

    Returns:
      None if no such object exists or the object found
    """
    try:
        res= model.objects.get(**kwargs)
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
 
def check_is_creator(request, model:models.Model, perm_string:str="edit, access or delete",**kwargs):
    """simple permission check for if the user is owner of object, return none if it is not, and creator object if the user sending the request is valid.
    There are tons of permission management options.

    in the future if you want to build more extensive permission check, you can do a serializer for object and an app for testing these object level permissions, but I will do rapid version here.

    Args: 
        request: http request
        model: the modal to search in, must be django.models.Model
        perm_string: message string passed if the test did not passed
        **kwargs: conditions to search for the model objects, same format as django.db.model.objects.get() function inputs

    Returns:
        tuple[Creator,model] | tuple[None,None]: creator if the user is owner and None if it is not or user not found, etc.
    
    """
    owner_id= get_object_or_None(Creator, user_id=request.user)
    # early terminate
    if owner_id==None:
        messages.error(request,"User not found.")
        return (None,None)
    instance=get_object_or_None(model,**kwargs)
    if instance==None:
        messages.error(request,"Instance object not found.")
        return (None,None)
    try:
        model._meta.get_field("creator_id")
    except:
        messages.error(request,"Invalid permission check detected.")
        return (None,None)
    if instance.creator_id==owner_id:
        return (owner_id,instance)
    else:
        messages.error(request,f"You are not creator of this object and don't have permission for {perm_string}")
        return (None,None)