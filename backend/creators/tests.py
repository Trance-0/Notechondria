import json
from datetime import datetime, timezone as dt_timezone
from unittest.mock import patch

from django.conf import settings
from django.contrib.auth.models import User
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from .models import Creator, VerificationChoices, VerificationCode, user_profile_path
from .utils import send_password_reset_email, send_registration_email


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


class AuthApiTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_user(
            username='admin',
            email='admin@example.com',
            password='change-me',
            is_active=True,
            is_staff=True,
            is_superuser=True,
        )

    def test_login_accepts_bootstrapped_admin_email(self):
        response = self.client.post(
            '/api/v1/auth/login/',
            {'email': 'admin@example.com', 'password': 'change-me'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn('token', response.json())

    def test_login_accepts_bootstrapped_admin_username(self):
        response = self.client.post(
            '/api/v1/auth/login/',
            {'email': 'admin', 'password': 'change-me'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn('token', response.json())

    @patch('creators.utils.logger')
    def test_send_password_reset_email_falls_back_to_logs_when_smtp_missing(self, logger):
        previous_host = settings.EMAIL_HOST
        previous_from = settings.DEFAULT_FROM_EMAIL
        settings.EMAIL_HOST = ''
        settings.DEFAULT_FROM_EMAIL = ''
        try:
            result = send_password_reset_email('demo@example.com', 'code-456')
        finally:
            settings.EMAIL_HOST = previous_host
            settings.DEFAULT_FROM_EMAIL = previous_from

        self.assertFalse(result['delivered'])
        self.assertTrue(result['fallback'])
        logger.warning.assert_called_once()

    def test_settings_update_supports_username_theme_and_api_base(self):
        token = Token.objects.create(user=self.admin)
        response = self.client.patch(
            '/api/v1/settings/',
            {
                'username': 'note-admin',
                'email': 'note-admin@example.com',
                'theme_preset': 'amber',
                'theme_mode': 'D',
                'api_base_url': 'https://notes.example.com/api/v1',
                'app_settings': {
                    'theme_preset': 'amber',
                    'theme_mode': 'D',
                    'api_base_url': 'https://notes.example.com/api/v1',
                    'log_preferences': {'frontend_logs': True},
                },
                'app_settings_updated_at': '2026-03-22T12:00:00Z',
            },
            format='json',
            HTTP_AUTHORIZATION=f'Token {token.key}',
        )

        self.assertEqual(response.status_code, 200)
        self.admin.refresh_from_db()
        creator = Creator.objects.get(user_id=self.admin)
        self.assertEqual(self.admin.username, 'note-admin')
        self.assertEqual(self.admin.email, 'note-admin@example.com')
        self.assertEqual(response.json()['theme_preset'], 'amber')
        self.assertEqual(response.json()['theme_mode'], 'D')
        self.assertEqual(response.json()['app_settings']['theme_preset'], 'amber')
        self.assertEqual(response.json()['app_settings']['log_preferences']['frontend_logs'], True)
        self.assertEqual(
            json.loads(creator.app_settings_json)['api_base_url'],
            'https://notes.example.com/api/v1',
        )
        self.assertTrue(response.json()['app_settings_updated_at'].startswith('2026-03-22T12:00:00'))

    def test_settings_get_includes_app_settings_mirror(self):
        token = Token.objects.create(user=self.admin)
        creator = Creator.objects.create(user_id=self.admin)
        creator.app_settings_json = json.dumps({
            'theme_preset': 'rose',
            'theme_mode': 'L',
            'api_base_url': 'https://mirror.example.com/api/v1',
            'log_preferences': {'copy_logs': True},
        })
        creator.app_settings_updated_at = datetime(2026, 3, 22, 12, 0, tzinfo=dt_timezone.utc)
        creator.save()

        response = self.client.get(
            '/api/v1/settings/',
            HTTP_AUTHORIZATION=f'Token {token.key}',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['app_settings']['theme_preset'], 'rose')
        self.assertEqual(response.json()['app_settings']['log_preferences']['copy_logs'], True)
        self.assertIn('app_settings_updated_at', response.json())

    def test_settings_reject_duplicate_username(self):
        other_user = User.objects.create_user(username='taken-name', email='taken@example.com', password='pw')
        Token.objects.create(user=other_user)
        token = Token.objects.create(user=self.admin)
        response = self.client.patch(
            '/api/v1/settings/',
            {'username': 'taken-name'},
            format='json',
            HTTP_AUTHORIZATION=f'Token {token.key}',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('username', response.json())

    def test_settings_reject_invalid_api_base_url(self):
        token = Token.objects.create(user=self.admin)
        response = self.client.patch(
            '/api/v1/settings/',
            {'api_base_url': 'localhost:9080/api/v1'},
            format='json',
            HTTP_AUTHORIZATION=f'Token {token.key}',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('api_base_url', response.json())
