from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0013_add_uuid_note_type_source_note"),
    ]

    operations = [
        migrations.AddField(
            model_name="course",
            name="icon",
            field=models.IntegerField(
                blank=True,
                help_text="Material Icons codePoint",
                null=True,
            ),
        ),
    ]
