from .base import *  # noqa

DEBUG = True
CELERY_TASK_ALWAYS_EAGER = True
MEDIA_ROOT = tempfile.mkdtemp()
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
