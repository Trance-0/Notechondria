# Generated by Django 4.2.10 on 2024-02-25 23:22

from django.db import migrations, models
import gptutils.models


class Migration(migrations.Migration):

    dependencies = [
        ('gptutils', '0013_alter_message_file_alter_message_image'),
    ]

    operations = [
        migrations.AlterField(
            model_name='message',
            name='file',
            field=models.FileField(blank=True, null=True, upload_to=gptutils.models.message_file_path),
        ),
        migrations.AlterField(
            model_name='message',
            name='file_id',
            field=models.CharField(max_length=255, null=True),
        ),
        migrations.AlterField(
            model_name='message',
            name='image',
            field=models.ImageField(blank=True, null=True, upload_to=gptutils.models.message_image_path),
        ),
    ]
