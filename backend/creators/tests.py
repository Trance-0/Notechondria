from django.contrib.auth.models import User
from django.test import TestCase

from .models import Creator, VerificationChoices, VerificationCode, user_profile_path


class CreatorModelTests(TestCase):
    def test_user_profile_path_uses_stable_filename(self):
        user = User.objects.create_user(username='alice', password='pw')
        creator = Creator.objects.create(user_id=user)

        path = user_profile_path(creator, 'portrait.png')

        self.assertEqual(path, f'user_upload/user_{user.id}/profile_pic/profile_latest.png')

    def test_verification_defaults(self):
        verification = VerificationCode.objects.create(code='abc123')

        self.assertEqual(verification.usage, VerificationChoices.AUTHENTICATE)
        self.assertEqual(verification.max_use, 1)
