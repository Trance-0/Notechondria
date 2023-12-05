"""
Place to set up database

After you modified these files, please remember to make migrations

1. run the following command
python manage.py makemigrations members
python manage.py migrate 
python manage.py runserver

2. If you modified the table too much, it is really easy to get errors,
please save the origional database and edit for postgre
"""

from django.conf import settings
from django.db import models
from django.utils.translation import gettext_lazy as _

class UserGroupChoices(models.TextChoices):
    """User group choices, may be more efficient if use django internal group"""
    ADMIN = "A", _("Admin")
    MANAGER = "M", _("Manager")
    NORMAL = "N", _("Normal")

class Creator(models.Model):
    """ for django built-in authentication: https://docs.djangoproject.com/en/4.2/ref/contrib/auth/ 
    """
    # This objects contains the username, password, first_name, last_name, and email of member.
    user_id = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        # when member is delete, user would also be deleted
        on_delete=models.CASCADE,
        null=False
    )
    motto = models.CharField(max_length=100,null=True)
    reputation = models.IntegerField(default=0,null=False)
    exp = models.IntegerField(default=0,null=False)
    social_link = models.URLField(max_length=255, null=True)
    credit_remains = models.IntegerField(default=0,null=False)

    # last_login and date_joined automatically created by user_id

    user_group = models.CharField(
        null=False, max_length=1, choices=UserGroupChoices.choices, default=UserGroupChoices.NORMAL
    )

    # user status is detemined by the group in user attribute

    def __str__(self):
        """for better list display"""
        return f"{self.user_id.get_full_name()}"

class ActivationCode(models.Model):
    """This is the activation code that will be used for create user.
    """
    code =models.CharField(max_length=255,null=False)
    expire_date=models.DateTimeField(null=True)
    max_use=models.IntegerField(default=1,null=False)
