"""Drop the InvitationCode, VerificationCode, and Session models.

0.1.106 — invitation codes, email-verification codes, and the
per-device Session table are all dead now. Casdoor owns signup,
password reset, and session lifecycle on its side
(`auth.trance-0.com`); Notechondria-side rows for those concepts
serve no purpose.

Pure DROP: no data is preserved (Sessions are ephemeral; the codes
are write-only on the backend; invitations were pre-cutover only).
"""
from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("creators", "0030_creator_casdoor_sub"),
    ]

    operations = [
        migrations.DeleteModel("InvitationCode"),
        migrations.DeleteModel("VerificationCode"),
        migrations.DeleteModel("Session"),
    ]
