from django.db import migrations, models
from django.db.models import Q


class Migration(migrations.Migration):

    dependencies = [
        ("notes", "0010_recyclebinentry"),
    ]

    operations = [
        migrations.AddField(
            model_name="course",
            name="client_course_id",
            field=models.CharField(blank=True, max_length=64, null=True),
        ),
        migrations.AddConstraint(
            model_name="course",
            constraint=models.UniqueConstraint(
                condition=Q(client_course_id__isnull=False),
                fields=("creator_id", "client_course_id"),
                name="unique_course_client_id_per_creator",
            ),
        ),
    ]
