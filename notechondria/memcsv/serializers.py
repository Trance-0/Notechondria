from django.contrib.auth.models import Group, User
from rest_framework import serializers




class MemCSV_Serializer(serializers.HyperlinkedModelSerializer):
    class Meta:
        model = User
        fields = ['url', 'username', 'email', 'groups'] 

