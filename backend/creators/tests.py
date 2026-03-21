from unittest.mock import patch

from django.conf import settings
from django.contrib.auth.models import User
from django.test import TestCase

from .models import Creator, VerificationChoices, VerificationCode, user_profile_path
from .utils import send_registration_email


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

    @patch('creators.utils.logger')
    def test_send_registration_email_falls_back_to_logs_when_smtp_missing(self, logger):
        previous_host = settings.EMAIL_HOST
        previous_from = settings.DEFAULT_FROM_EMAIL
        settings.EMAIL_HOST = ''
        settings.DEFAULT_FROM_EMAIL = ''
        try:
            result = send_registration_email('demo@example.com', 'code-123')
        finally:
            settings.EMAIL_HOST = previous_host
            settings.DEFAULT_FROM_EMAIL = previous_from

        self.assertFalse(result['delivered'])
        self.assertTrue(result['fallback'])
        logger.warning.assert_called_once()
