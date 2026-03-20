from .settings import *  # noqa: F401,F403

DEBUG = True

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': ':memory:',
    }
}

PASSWORD_HASHERS = [
    'django.contrib.auth.hashers.MD5PasswordHasher',
]

MIDDLEWARE = [m for m in MIDDLEWARE if m != 'debug_toolbar.middleware.DebugToolbarMiddleware']
INSTALLED_APPS = [app for app in INSTALLED_APPS if app not in {'debug_toolbar', 'memcsv', 'rest_framework'}]

LOGGING = {
    'version': 1,
    'disable_existing_loggers': True,
}

ROOT_URLCONF = 'notechondria.urls_test'
