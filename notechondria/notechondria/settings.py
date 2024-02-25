"""
Django settings for notechondria project.

Generated by 'django-admin startproject' using Django 3.1.3.

For more information on this file, see
https://docs.djangoproject.com/en/4.2/topics/settings/

For the full list of settings and their values, see
https://docs.djangoproject.com/en/4.2/ref/settings/
"""

import os
from pathlib import Path
from dotenv import load_dotenv
from datetime import datetime

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent

load_dotenv(os.path.join(BASE_DIR,'.env'))

# Quick-start development settings - unsuitable for production
# See https://docs.djangoproject.com/en/4.2/howto/deployment/checklist/

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = os.getenv('SECRET_KEY')

# SECURITY WARNING: don't run with debug turned on in production!
# DEBUG = False
DEBUG = os.getenv('DEBUG', 'False') == 'True'

ALLOWED_HOSTS = os.getenv("ALLOWED_HOSTS").split(" ")


# Application definition

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    # apps created
    'gptutils',
    'notes',
    'creators',
    # debugger
    'debug_toolbar'
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'debug_toolbar.middleware.DebugToolbarMiddleware',
]

# internal ip for debug_toolbar
if DEBUG:
    import socket  # only if you haven't already imported this
    hostname, _, ips = socket.gethostbyname_ex(socket.gethostname())
    INTERNAL_IPS = [ip[: ip.rfind(".")] + ".1" for ip in ips] + ["127.0.0.1", "10.0.2.2"]

# add trusted CDN
CSRF_TRUSTED_ORIGINS = [f"http://localhost:{os.getenv('NGINX_PORT', 80)}"]

ROOT_URLCONF = 'notechondria.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        # this is the place to put global templates
        'DIRS': [os.path.join(BASE_DIR, 'notechondria','templates')],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
                'notechondria.views.is_offline'
            ],
            'libraries': {
                'svg_tags': 'notechondria.templatetags.svg_tags',
            }
        },
    },
]

# Session settings
# https://docs.djangoproject.com/en/3.2/ref/settings/#std-setting-SESSION_COOKIE_AGE
# We set to at most 3 days
SESSION_COOKIE_AGE=259200

WSGI_APPLICATION = 'notechondria.wsgi.application'

# Logging
# https://docs.djangoproject.com/en/4.2/topics/logging/

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        # print level in console
        'console': {
            'level': 'INFO',
            'class': 'logging.StreamHandler',
            'formatter': 'verbose',
        },
        # print level in log file
        'file': {
            # de-comment the line below for detailed (super detailed) debug in django
            # 'level': 'DEBUG',
            'level': 'INFO',
            'class': 'logging.FileHandler',
            # if you need to store it outside of current project folder, remove the join base part.
            'filename': os.path.join(BASE_DIR,os.path.join("logs",f"{os.getenv('DJANGO_LOG_FILE_NAME', 'logs')}-{datetime.now().strftime('%Y%m%d')}.log")),
            'formatter': 'verbose',
            'encoding':'utf8',
        },
    },
    'formatters': {
        'verbose': {
            'format': u'%(levelname)s [%(asctime)s] %(name)s.%(funcName)s:%(lineno)s- %(message)r',
        },
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'level': os.getenv('DJANGO_LOG_LEVEL', 'INFO'),
        },
    },
    # all the logging will propagate to root. so use root to save your log
    'root': {
        'handlers': ['file', ],
        'level': 'DEBUG',
    },
}

# Database
# https://docs.djangoproject.com/en/4.2/ref/settings/#databases

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'postgres',
        'USER': os.getenv('POSTGRE_USERNAME'),
        'PASSWORD': os.getenv('POSTGRE_PASSWORD'),
        'HOST': "localhost" if DEBUG else os.getenv('POSTGRE_HOST'),
        'PORT': os.getenv('POSTGRE_PORT')
    }
}


# Password validation
# https://docs.djangoproject.com/en/4.2/ref/settings/#auth-password-validators

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',  
        "OPTIONS": {
            "min_length": 9,
        },
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]


# Internationalization
# https://docs.djangoproject.com/en/4.2/topics/i18n/

LANGUAGE_CODE = 'en-us'

TIME_ZONE = 'UTC'

USE_I18N = True

USE_L10N = True

USE_TZ = True

# Automatic primary key for those who don't set, and the default feature name is id
# https://docs.djangoproject.com/en/3.2/topics/db/models/#automatic-primary-key-fields
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# Static files (CSS, JavaScript, Images)
# https://docs.djangoproject.com/en/4.2/howto/static-files/

# you should not use django to process your static files, the static url should be set to other file providing url
STATIC_URL = '/static/'

# static file in the project folder (global)
STATICFILES_DIRS = [
    os.path.join(BASE_DIR, 'static'),
]

# this is the location where collect static will run, set it to the service directory of static url in production
STATIC_ROOT = os.path.join(BASE_DIR, 'productionfiles/') if DEBUG else os.getenv('PRODUCTION_STATIC_ROOT')

# Image files (jpg, jpeg)
# reference: https://djangocentral.com/uploading-images-with-django/

# Base url to serve media files
MEDIA_URL = '/media/'

# Path where media is stored
MEDIA_ROOT = os.path.join(BASE_DIR, 'media') if DEBUG else os.getenv('PRODUCTION_MEDIA_ROOT')

# Offline development tag
OFFLINE = False

# login url

LOGIN_URL="/creators/login"

# LOGIN_REDIRECT_URL="/creators/profile"