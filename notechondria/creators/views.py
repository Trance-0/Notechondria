
from PIL import Image

from django.contrib.auth.decorators import login_required
from django.http import HttpResponse
from django.contrib.auth.models import User
from django.contrib import messages
from django.shortcuts import redirect, render, get_object_or_404
from django.contrib.auth import login, logout, authenticate

from .forms import LoginForm, RegisterForm, EditForm
from .models import Creator


# Create your views here.
def creators(request):
    """processing general requests from creator"""
    if request.method == "POST":
        form = LoginForm(request.POST)
        return render(request, "login_bootstrap.html", {"form": form})
    return HttpResponse("To be implemented creator recruting site")


def login_request(request):
    """processing the login request from user

    form generated from From class
    Form processing code reference: https://docs.djangoproject.com/en/4.2/topics/forms/

    If post, the do data validation
    If get, return the form
    """
    # if this is a POST request we need to process the form data
    if request.method == "POST":
        # create a form instance and populate it with data from the request:
        form = LoginForm(request.POST)
        # check whether it's valid:
        if form.is_valid():
            # process the data in form.cleaned_data as required
            username = form.cleaned_data["username"]
            password = form.cleaned_data["password"]
            user = authenticate(username=username, password=password)
            if user is not None:
                login(request, user)
                # set last login 
                creator=Creator.objects.get(user_id=user)
                creator.save()
                return redirect("home")
            messages.warning(request, "User password mismatch")
        else:
            messages.warning(request, "User not found")
        # redirect to a new URL:
        return redirect("home")
    # if a GET (or any other method) we'll create a blank form
    form = LoginForm()
    return render(request, "login_bootstrap.html", {"form": form})


def register_request(request):
    """Process the register request

    If post, the do data validation
    If get, return the form
    """
    if request.method == "POST":
        # create a form instance and populate it with data from the request:
        form = RegisterForm(request.POST,request.FILES)
        # check whether it's valid:
        if form.is_valid():
            username=form.cleaned_data["user_name"]
            password=form.cleaned_data["password"]
            form.save()
            # redirect to a new URL:
            messages.info(request, "User registration success")
            user = authenticate(username=username, password=password)
            if user is not None:
                login(request, user)
            return redirect("home")
        if form.errors:
            for key, value in form.errors.items():
                messages.error(request, f"validation error {key},{value}")
        return render(request, "register_bootstrap.html", {"form": form})
    # processing GET request
    form = RegisterForm()
    return render(request, "register_bootstrap.html", {"form": form})


def logout_request(request):
    """django logout"""
    logout(request)
    return redirect("home")


def get_profile(request, username):
    """Return the profile for the user

    If the user is the owner of the page, also add other attributes for edits
    """
    user_instance = get_object_or_404(User, username=username)
    creator_instance = get_object_or_404(Creator, user_id=user_instance)
    # test for edit permission
    can_edit = False
    # placeholder value
    if creator_instance.user_id == request.user:
        can_edit = True
        # render forms for review
        # initalized form factories if other attributes added
    return render(
        request,
        "profile_bootstrap.html",
        {
            "can_edit": can_edit,
            "userinfo": creator_instance,
        },
    )


@login_required
def edit_profile(request, username):
    """Form for edit profile"""
    # test consistency
    if request.user.username != username:
        messages.warning(request, "Do not change other's password")
    user_instance = get_object_or_404(User, username=username)
    creator = get_object_or_404(Creator, user_id=user_instance)
    if request.method == "POST":
        # for lazy, we just return the register form, could be more fancy if we want to.
        profile_form = EditForm(request.POST,request.FILES, instance=creator)
        if profile_form.is_valid():
            # process the data in form.cleaned_data as required, validation in form class
            username=profile_form.cleaned_data["user_name"]
            password=profile_form.cleaned_data["password"]
            creator=profile_form.save()
            user = authenticate(username=username, password=password)
            if user is not None:
                login(request, user)
            # redirect to a new URL:
            messages.success(request, "edit profile success")
            return redirect("creators:profile", username=username)
        if profile_form.errors:
            for key, value in profile_form.errors.items():
                messages.error(request, f"validation error {key},{value}")
        messages.error(request, "edit profile form invalid")
    else:
        profile_form = EditForm(instance=creator)
    return render(request, "edit_profile_bootstrap.html", {"form": profile_form})
