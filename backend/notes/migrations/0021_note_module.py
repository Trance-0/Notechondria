from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0020_note_name"),
    ]

    operations = [
        migrations.AddField(
            model_name="note",
            name="module",
            field=models.CharField(blank=True, default="", max_length=160),
        ),
    ]
