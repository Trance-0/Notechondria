# Generated by Django 3.1.3 on 2024-02-10 22:47

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('gptutils', '0004_auto_20240207_1608'),
    ]

    operations = [
        migrations.AddField(
            model_name='conversation',
            name='total_completion_tokens',
            field=models.IntegerField(default=0),
        ),
        migrations.AddField(
            model_name='conversation',
            name='total_prompt_tokens',
            field=models.IntegerField(default=0),
        ),
    ]
