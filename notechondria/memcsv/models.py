import os
from django.db import models
from creators.models import Creator
from django.utils.translation import gettext_lazy as _
# Create your models here.

def MemCSV_file_path(instance, filename):
    """ 
    file will be uploaded to MEDIA_ROOT/user_<id>/<filename>
    https://docs.djangoproject.com/en/dev/ref/models/fields/#django.db.models.FileField.upload_to
    """
    # return "profile_pic/user_{0}/{1}".format(instance.user.id, filename)
    # we save only one latest image.
    _name, _extension = os.path.splitext(filename)
    return "user_upload/user_{0}/mem_CSV/csv_{1}.csv".format(instance.creator_id.user_id.id,instance.id)


class MemCSV(models.Model):
    # This objects contains the username, password, first_name, last_name, and email of member.
    creator_id = models.ForeignKey(
        Creator,
        # when conversation is deleted, whether the creator should also be deleted
        # Is it a creator specifically within the mem chatbox? 
        # That is a mini-Creator that is created dependent on the logged in user model and exist only within the Mem_Training App deleted once conversation is gone?
        on_delete=models.CASCADE,
        null=False,
    )
    
    csv_file = models.FileField(upload_to=MemCSV_file_path,null=False)
    title = models.CharField(max_length=100, null=True) # container_name
    sharing_id = models.CharField(max_length=36,unique=True,null=True) # rememeber to change back afterwards
   


    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created=models.DateTimeField(auto_now_add=True,null=False)

class MemRecord(models.Model):
    mem_id = models.ForeignKey(
        MemCSV,
        # when record is deleted, whether the creator should also be deleted
        on_delete=models.CASCADE,
        null=False,
    )
    sharing_id = models.CharField(max_length=36,unique=True,null=False)

    # last_use and date_created automatically created, for these field, create one time value to timezone.now()
    date_created= models.DateTimeField(auto_now_add=True,null=False)




class WordDict (models.Model): # I need think that all these pairs are stored in as a referece id diseect content of the file
    
    container = models.ForeignKey(
        MemCSV,
        db_index=True,
        on_delete=models.CASCADE,
        related_name='values',
        )
    #add other values like or more
    Japanese_Key= models.CharField(max_length=50,null=False)
    English_Value =models.CharField(max_length=50,null=False)
    
    
    

    
  
    
    
     
     
     
     


 

    



