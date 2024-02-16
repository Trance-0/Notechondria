# Generated by Django 4.2.10 on 2024-02-12 20:44

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('gptutils', '0007_conversation_param_alter_conversation_model'),
    ]

    operations = [
        migrations.AddField(
            model_name='message',
            name='file_id',
            field=models.CharField(blank=True, max_length=255, null=True),
        ),
        migrations.AlterField(
            model_name='conversation',
            name='param',
            field=models.CharField(max_length=255, null=True),
        ),
        migrations.AlterField(
            model_name='message',
            name='text',
            field=models.TextField(blank=True, null=True),
        ),
    ]