from django.db import models
from creators.models import Creator
from django.utils.translation import gettext_lazy as _
# Create your models here.

class MemCSV(models.Model):
    # This objects contains the username, password, first_name, last_name, and email of member.
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleteted, wheather the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    csv_file = models.FileField(upload_to='memcsv/')
    sharing_id = models.CharField(max_length=36,unique=True,null=False)
    title = models.CharField(max_length=100, null=True)

    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)

class MemRecord(models.Model):
    mem_id = models.ForeignKey(
        MemCSV,
        # when record is deleteted, wheather the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    sharing_id = models.CharField(max_length=36,unique=True,null=False)

    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)
    

