from .settings import *  # noqa: F401,F403

DEBUG = True
SECRET_KEY = 'notechondria-test-secret-key'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': ':memory:',
    }
}

PASSWORD_HASHERS = [
    'django.contrib.auth.hashers.MD5PasswordHasher',
]

LOGGING = {
    'version': 1,
    'disable_existing_loggers': True,
}

ROOT_URLCONF = 'notechondria.urls_test'
