from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0018_note_custom_meta"),
    ]

    operations = [
        migrations.AddField(
            model_name="note",
            name="git_path",
            field=models.CharField(blank=True, max_length=512, null=True),
        ),
    ]
