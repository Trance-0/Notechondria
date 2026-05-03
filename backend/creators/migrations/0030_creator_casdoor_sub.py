from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0029_creator_mcp_skill_md_githubintegration"),
    ]

    operations = [
        migrations.AddField(
            model_name="creator",
            name="casdoor_sub",
            field=models.CharField(
                blank=True,
                db_index=True,
                default="",
                help_text=(
                    "Soft pointer to the Casdoor user record (the `sub` "
                    "/ `id` claim on the JWT). Populated by "
                    "`CasdoorJWTAuthentication` on first sign-in via "
                    "Casdoor; left empty for accounts that still use "
                    "the legacy MultiSessionAuthentication path. See "
                    "docs/integrations/casdoor-migration.md."
                ),
                max_length=128,
            ),
        ),
    ]
