# Generated by Django 3.1.3 on 2024-02-10 22:54

import datetime
from django.db import migrations, models
from django.utils.timezone import utc


class Migration(migrations.Migration):

    dependencies = [
        ('creators', '0012_auto_20240210_1647'),
    ]

    operations = [
        migrations.AlterField(
            model_name='verificationcode',
            name='code',
            field=models.CharField(default='CkFqbJ', max_length=255),
        ),
        migrations.AlterField(
            model_name='verificationcode',
            name='expire_date',
            field=models.DateTimeField(default=datetime.datetime(2024, 2, 10, 23, 4, 55, 661046, tzinfo=utc)),
        ),
    ]
