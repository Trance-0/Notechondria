# Generated by Django 4.2.10 on 2024-02-29 02:53

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('notes', '0001_initial'),
    ]

    operations = [
        migrations.AlterField(
            model_name='noteblock',
            name='args',
            field=models.CharField(max_length=256),
        ),
    ]