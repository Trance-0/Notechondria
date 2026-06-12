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
    # MD5 first: set_password stays fast for the hundreds of test users.
    'django.contrib.auth.hashers.MD5PasswordHasher',
    # Needed to verify `bcrypt$<hash>` values mirrored from Casdoor
    # (creators/casdoor_password.py) — see CasdoorPasswordClaimsSyncTests.
    'django.contrib.auth.hashers.BCryptPasswordHasher',
]

LOGGING = {
    'version': 1,
    'disable_existing_loggers': True,
}

ROOT_URLCONF = 'notechondria.urls_test'
