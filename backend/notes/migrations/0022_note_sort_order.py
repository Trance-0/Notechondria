from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0021_note_module"),
    ]

    operations = [
        migrations.AddField(
            model_name="note",
            name="sort_order",
            field=models.IntegerField(db_index=True, default=0),
        ),
    ]
