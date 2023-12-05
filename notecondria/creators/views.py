from django.contrib.auth.decorators import login_required
from django.forms import modelformset_factory

from django.http import HttpResponse
from django.contrib.auth.models import User
from django.contrib import messages
from django.shortcuts import redirect, render, get_object_or_404
from django.contrib.auth import login, logout, authenticate

from .forms import LoginForm, RegisterForm
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
                return redirect("home")
            else:
                messages.warning(request, "User password mismatch")
        else:
            messages.warning(request, "User not found")
        # redirect to a new URL:
        return redirect("home")
    # if a GET (or any other method) we'll create a blank form
    else:
        form = LoginForm()
        return render(request, "login_bootstrap.html", {"form": form})


def register_request(request):
    """Process the register request

    If post, the do data validation
    If get, return the form
    """
    if request.method == "POST":
        # create a form instance and populate it with data from the request:
        form = RegisterForm(request.POST)
        # check whether it's valid:
        if form.is_valid():
            # process the data in form.cleaned_data as required, validation in form class
            username = form.cleaned_data["user_name"]
            password = form.cleaned_data["password"]
            firstname = form.cleaned_data["first_name"]
            lastname = form.cleaned_data["last_name"]
            email = form.cleaned_data["email"]
            # create user
            member = form.save(commit=False)
            user = User.objects.create(
                username=username, first_name=firstname, last_name=lastname, email=email
            )
            user.set_password(password)
            # the user will not be save automatically
            user.save()
            member.user_id = user
            member.save()
            # redirect to a new URL:
            messages.info(request, "User registration success")
            user = authenticate(username=username, password=password)
            if user is not None:
                login(request, user)
            return redirect("home")
        else:
            if form.errors:
                for key, value in form.errors.items():
                    messages.error(request, f"{key},{value}")
            return redirect("creator:register")
    else:
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
    member_instance = get_object_or_404(Creator, user_id=user_instance)
    # test for edit permission
    can_edit = False
    # placeholder value
    if member_instance.user_id == request.user:
        can_edit = True
        # render forms for review
        # initalized form factories if other attributes added
    return render(
        request,
        "profile_bootstrap.html",
        {
            "can_edit": can_edit,
            "userinfo": member_instance,
        },
    )


@login_required
def edit_profile(request, username):
    """Form for edit profile"""
    # test consistency
    if request.user.username != username:
        messages.warning(request, "Do not change other's password")
    user_instance = get_object_or_404(User, username=username)
    membmer = get_object_or_404(Creator, user_id=user_instance)
    if request.method == "POST":
        # for lazy, we just return the register form, could be more fancy if we want to.
        profile_form = RegisterForm(request.POST, instance=membmer)
        if profile_form.is_valid():
            # process the data in form.cleaned_data as required, validation in form class
            password = profile_form.cleaned_data["password"]
            user_instance.username = profile_form.cleaned_data["user_name"]
            # django generic class function, password validation in form module
            user_instance.set_password(password)
            user_instance.firstname = profile_form.cleaned_data["first_name"]
            user_instance.lastname = profile_form.cleaned_data["last_name"]
            user_instance.email = profile_form.cleaned_data["email"]

            # the user will not be save automatically
            user_instance.save()
            profile_form.save()
            user = authenticate(username=username, password=password)
            if user is not None:
                login(request, user)
            # redirect to a new URL:
            messages.success(request, "edit profile success")
            return redirect("creators:profile", username=username)
        else:
            messages.error(request, "edit profile form invalid")
    else:
        profile_form = RegisterForm(instance=membmer)
    return render(request, "edit_profile_bootstrap.html", {"form": profile_form})
