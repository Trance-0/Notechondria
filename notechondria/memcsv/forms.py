from django import forms
from .models import MemCSV



# Django ModelForm https://docs.djangoproject.com/en/5.0/topics/forms/modelforms/#overriding-modelform-clean-method
# A form that User input File and its Title
class MemCSVForm(forms.ModelForm):
    class Meta:
        model = MemCSV
        fields = ['title', 'csv_file']  #these are the two feilds we use to instantiate
        
        
        
#class Recod


  # prompt =
  # answer =
   
   
    

    
    
 
 