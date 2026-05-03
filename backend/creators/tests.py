import json
from datetime import datetime, timezone as dt_timezone
from unittest.mock import patch

from django.conf import settings
from django.contrib.auth.models import User
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from .models import Creator, InvitationCode, VerificationChoices, VerificationCode, user_profile_path
from .utils import issue_registration_code, send_password_reset_email, send_registration_email


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


class RegistrationFlowTests(TestCase):
    """Full registration cycle: register → verify → login."""

    def setUp(self):
        self.client = APIClient()

    @patch('creators.utils.smtp_is_configured', return_value=False)
    @patch('creators.utils.log_manual_verification_code')
    def test_register_creates_inactive_user_and_sends_code(self, mock_log, _smtp):
        response = self.client.post(
            '/api/v1/auth/register/',
            {
                'username': 'alice',
                'email': 'alice@example.com',
                'password': 'Strong1pw',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 201)
        user = User.objects.get(email='alice@example.com')
        self.assertFalse(user.is_active)
        self.assertEqual(user.username, 'alice')
        # The verification code was logged (SMTP not configured).
        mock_log.assert_called_once()
        logged_code = mock_log.call_args[0][1]  # positional: email, code, reason
        self.assertEqual(len(logged_code), 6)
        self.assertTrue(logged_code.isdigit())

    @patch('creators.utils.smtp_is_configured', return_value=False)
    @patch('creators.utils.log_manual_verification_code')
    def test_register_then_verify_activates_user(self, mock_log, _smtp):
        self.client.post(
            '/api/v1/auth/register/',
            {
                'username': 'bob',
                'email': 'bob@example.com',
                'password': 'Strong1pw',
            },
            format='json',
        )
        plaintext_code = mock_log.call_args[0][1]
        response = self.client.post(
            '/api/v1/auth/verify-email/',
            {'email': 'bob@example.com', 'code': plaintext_code},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn('token', response.json())
        user = User.objects.get(email='bob@example.com')
        self.assertTrue(user.is_active)

    def test_register_rejects_weak_password_no_uppercase(self):
        response = self.client.post(
            '/api/v1/auth/register/',
            {'username': 'weak', 'email': 'w@example.com', 'password': 'alllower1'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('password', response.json())

    def test_register_rejects_short_password(self):
        response = self.client.post(
            '/api/v1/auth/register/',
            {'username': 'short', 'email': 's@example.com', 'password': 'Ab1'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('password', response.json())

    def test_register_rejects_duplicate_username(self):
        User.objects.create_user(username='taken', email='t@example.com', password='pw')
        response = self.client.post(
            '/api/v1/auth/register/',
            {'username': 'taken', 'email': 'new@example.com', 'password': 'Strong1pw'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('username', response.json())

    def test_register_requires_username(self):
        response = self.client.post(
            '/api/v1/auth/register/',
            {'email': 'no-user@example.com', 'password': 'Strong1pw'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('username', response.json())


class InvitationCodeTests(TestCase):
    """Invitation code gate on registration."""

    def setUp(self):
        self.client = APIClient()

    @patch('creators.utils.smtp_is_configured', return_value=False)
    @patch('creators.utils.log_manual_verification_code')
    def test_invitation_code_required_when_codes_exist(self, mock_log, _smtp):
        InvitationCode.objects.create(code_hash=InvitationCode.hash_code('secret-invite'))
        response = self.client.post(
            '/api/v1/auth/register/',
            {
                'username': 'carol',
                'email': 'carol@example.com',
                'password': 'Strong1pw',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('invitation_code', response.json())

    @patch('creators.utils.smtp_is_configured', return_value=False)
    @patch('creators.utils.log_manual_verification_code')
    def test_valid_invitation_code_allows_registration(self, mock_log, _smtp):
        InvitationCode.objects.create(
            code_hash=InvitationCode.hash_code('secret-invite'),
            label='test',
            max_uses=5,
        )
        response = self.client.post(
            '/api/v1/auth/register/',
            {
                'username': 'dave',
                'email': 'dave@example.com',
                'password': 'Strong1pw',
                'invitation_code': 'secret-invite',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 201)
        invite = InvitationCode.objects.get(label='test')
        self.assertEqual(invite.times_used, 1)

    @patch('creators.utils.smtp_is_configured', return_value=False)
    @patch('creators.utils.log_manual_verification_code')
    def test_wrong_invitation_code_rejected(self, mock_log, _smtp):
        InvitationCode.objects.create(code_hash=InvitationCode.hash_code('real'))
        response = self.client.post(
            '/api/v1/auth/register/',
            {
                'username': 'eve',
                'email': 'eve@example.com',
                'password': 'Strong1pw',
                'invitation_code': 'wrong-guess',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 400)

    @patch('creators.utils.smtp_is_configured', return_value=False)
    @patch('creators.utils.log_manual_verification_code')
    def test_no_invitation_codes_in_db_allows_open_registration(self, mock_log, _smtp):
        """When no InvitationCode records exist, anyone can register."""
        response = self.client.post(
            '/api/v1/auth/register/',
            {
                'username': 'frank',
                'email': 'frank@example.com',
                'password': 'Strong1pw',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 201)

    def test_invitation_code_model_auto_hashes_plaintext_on_save(self):
        invite = InvitationCode(code_hash='my-plain-code', label='auto')
        invite.save()
        self.assertEqual(len(invite.code_hash), 64)
        self.assertEqual(invite.code_hash, InvitationCode.hash_code('my-plain-code'))


class PasswordResetFlowTests(TestCase):
    """Password reset with 6-digit hashed codes."""

    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username='resetuser',
            email='reset@example.com',
            password='OldPass1!',
            is_active=True,
        )

    @patch('creators.utils.smtp_is_configured', return_value=False)
    @patch('creators.utils.log_manual_verification_code')
    def test_password_reset_full_cycle(self, mock_log, _smtp):
        # Request reset
        response = self.client.post(
            '/api/v1/auth/password-reset/',
            {'email': 'reset@example.com'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        plaintext_code = mock_log.call_args[0][1]
        self.assertEqual(len(plaintext_code), 6)

        # Confirm reset with new password
        response = self.client.post(
            '/api/v1/auth/password-reset/confirm/',
            {
                'email': 'reset@example.com',
                'code': plaintext_code,
                'password': 'NewPass2!',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)

        # Old password no longer works
        response = self.client.post(
            '/api/v1/auth/login/',
            {'email': 'reset@example.com', 'password': 'OldPass1!'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)

        # New password works
        response = self.client.post(
            '/api/v1/auth/login/',
            {'email': 'reset@example.com', 'password': 'NewPass2!'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn('token', response.json())

    def test_password_reset_rejects_unknown_email(self):
        response = self.client.post(
            '/api/v1/auth/password-reset/',
            {'email': 'nobody@example.com'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)


class VerificationCodeModelTests(TestCase):
    """Tests for the 6-digit hashed verification code model."""

    def test_generate_code_returns_6_digit_string(self):
        vc = VerificationCode()
        plaintext = vc.generate_code()
        self.assertEqual(len(plaintext), 6)
        self.assertTrue(plaintext.isdigit())

    def test_generate_code_stores_sha256_hash(self):
        vc = VerificationCode()
        plaintext = vc.generate_code()
        self.assertEqual(len(vc.code), 64)  # SHA-256 hex digest
        self.assertEqual(vc.code, VerificationCode.hash_code(plaintext))


class OAuthBindRejectionTests(TestCase):
    """Public OAuth endpoints must refuse intent='bind'.

    Binding requires an authenticated user — routing the bind through the
    unauthenticated endpoint would either (a) log the caller in as whoever
    owns the matching email or (b) mint a brand-new account from the
    OAuth-provided username/email. Either outcome silently overwrites the
    existing account from the original user's perspective, which is the
    bug this guard exists to prevent.
    """

    def setUp(self):
        self.client = APIClient()

    def test_google_public_endpoint_rejects_bind_intent(self):
        response = self.client.post(
            '/api/v1/auth/google/',
            {'code': 'fake-authorization-code', 'intent': 'bind'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('bind', response.json().get('detail', '').lower())

    def test_github_public_endpoint_rejects_bind_intent(self):
        response = self.client.post(
            '/api/v1/auth/github/',
            {'code': 'fake-authorization-code', 'intent': 'bind'},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('bind', response.json().get('detail', '').lower())

    def test_hash_code_is_deterministic(self):
        self.assertEqual(
            VerificationCode.hash_code('123456'),
            VerificationCode.hash_code('123456'),
        )
        self.assertNotEqual(
            VerificationCode.hash_code('123456'),
            VerificationCode.hash_code('654321'),
        )

    def test_issue_registration_code_returns_tuple(self):
        User.objects.create_user(username='u', email='u@x.com', password='pw')
        vc, plaintext = issue_registration_code('u@x.com')
        self.assertIsInstance(vc, VerificationCode)
        self.assertEqual(len(plaintext), 6)
        self.assertEqual(vc.code, VerificationCode.hash_code(plaintext))


class GithubSyncTests(TestCase):
    """Coverage for the experimental GitHub data-sync feature
    (`creators.services.github_sync`, `GithubSync*ApiView`)."""

    def setUp(self):
        self.user = User.objects.create_user(
            username='gh-sync', email='gh@example.com', password='pw',
        )
        self.creator = Creator.objects.create(user_id=self.user)
        self.client_api = APIClient()

    def _auth(self):
        from creators.models import Session

        session = Session.create_for_user(self.user)
        self.client_api.credentials(HTTP_AUTHORIZATION=f'Token {session.key}')

    def test_status_view_requires_auth(self):
        resp = self.client_api.get('/api/v1/integrations/github/status/')
        self.assertIn(resp.status_code, (401, 403))

    def test_status_view_disconnected_when_no_integration(self):
        self._auth()
        resp = self.client_api.get('/api/v1/integrations/github/status/')
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(resp.json()['connected'])

    def test_callback_upserts_by_installation_id(self):
        from creators.models import GithubIntegration

        self._auth()
        resp = self.client_api.post(
            '/api/v1/integrations/github/callback/',
            {
                'installation_id': '12345',
                'account_login': 'octocat',
                'repo_full_name': 'octocat/notes-backup',
                'repo_default_branch': 'main',
            },
            format='json',
        )
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json()['connected'])
        # Re-POST with new repo: should update existing row, not duplicate.
        resp = self.client_api.post(
            '/api/v1/integrations/github/callback/',
            {
                'installation_id': '12345',
                'repo_full_name': 'octocat/notes-backup-2',
            },
            format='json',
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(
            GithubIntegration.objects.filter(creator=self.creator).count(),
            1,
        )
        self.assertEqual(
            GithubIntegration.objects.get(creator=self.creator).repo_full_name,
            'octocat/notes-backup-2',
        )

    def test_status_view_after_callback_returns_repo(self):
        self._auth()
        self.client_api.post(
            '/api/v1/integrations/github/callback/',
            {
                'installation_id': '12345',
                'account_login': 'octocat',
                'repo_full_name': 'octocat/notes-backup',
            },
            format='json',
        )
        resp = self.client_api.get('/api/v1/integrations/github/status/')
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertTrue(body['connected'])
        self.assertEqual(body['repo_full_name'], 'octocat/notes-backup')

    def test_disconnect_clears_integration(self):
        from creators.models import GithubIntegration

        self._auth()
        self.client_api.post(
            '/api/v1/integrations/github/callback/',
            {'installation_id': '99'},
            format='json',
        )
        resp = self.client_api.delete('/api/v1/integrations/github/status/')
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(resp.json()['connected'])
        self.assertFalse(
            GithubIntegration.objects.filter(creator=self.creator).exists()
        )

    def test_jwt_signer_round_trips_with_test_keypair(self):
        """The JWT signer must produce a token verifiable by the public
        half of the same key, with the App's client_id as `iss`. We
        skip the network call entirely — only exercise the crypto path."""
        try:
            import jwt as _jwt
            from cryptography.hazmat.primitives import serialization
            from cryptography.hazmat.primitives.asymmetric import rsa
        except ImportError:
            self.skipTest("pyjwt + cryptography not installed in this venv")

        from creators.services.github_sync import _build_app_jwt

        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        pem_private = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ).decode('utf-8')
        pem_public = key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        ).decode('utf-8')

        token = _build_app_jwt('Iv1.fake-app-id', pem_private)
        decoded = _jwt.decode(token, pem_public, algorithms=['RS256'])
        self.assertEqual(decoded['iss'], 'Iv1.fake-app-id')
        # `iat` is backdated 60s; `exp` is 9 minutes ahead.
        self.assertLess(decoded['iat'], decoded['exp'])
        self.assertLessEqual(decoded['exp'] - decoded['iat'], 11 * 60)

    def test_jwt_signer_normalizes_escaped_pem(self):
        """Operators store the PEM with literal `\\n` escapes in env
        files; the signer must convert before passing to cryptography."""
        try:
            import jwt as _jwt  # noqa: F401
            from cryptography.hazmat.primitives import serialization
            from cryptography.hazmat.primitives.asymmetric import rsa
        except ImportError:
            self.skipTest("pyjwt + cryptography not installed in this venv")

        from creators.services.github_sync import _build_app_jwt

        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        pem_private = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ).decode('utf-8')
        escaped = pem_private.replace('\n', '\\n')
        # Should not raise even though `escaped` is a single-line value.
        _build_app_jwt('Iv1.fake-app-id', escaped)

    def test_materialize_produces_expected_paths(self):
        """`materialize` covers profile, courses, notes (+ sidecar),
        planner, manifest, and README for a seeded creator."""
        from courses.models import Course
        from notes.models import Note
        from notechondria.utils import generate_unique_id
        from creators.services.github_sync import materialize

        course = Course.objects.create(
            creator_id=self.creator,
            slug='inbox',
            title='Inbox',
            description='',
            is_default=True,
        )
        note = Note.objects.create(
            creator_id=self.creator,
            course_id=course,
            sharing_id=generate_unique_id(Note, 'sharing_id'),
            title='Hello',
            content='# hello',
            custom_meta='{"tag": "demo"}',
        )
        files = materialize(self.creator)
        paths = {f.path for f in files}
        self.assertIn('README.md', paths)
        self.assertIn('manifest.json', paths)
        self.assertIn('profile/creator.json', paths)
        self.assertIn('profile/skill.md', paths)
        self.assertIn('courses/inbox.json', paths)
        self.assertIn(f'notes/{note.uuid.hex}.md', paths)
        self.assertIn(f'notes/{note.uuid.hex}.meta.json', paths)
        self.assertIn('planner/events.json', paths)
        self.assertIn('planner/feeds.json', paths)
        # Note frontmatter should carry the user's custom_meta keys.
        body = next(
            f.content_bytes for f in files
            if f.path == f'notes/{note.uuid.hex}.md'
        ).decode('utf-8')
        self.assertIn('tag: "demo"', body)

    def test_repos_endpoint_rejects_when_disconnected(self):
        self._auth()
        resp = self.client_api.get('/api/v1/integrations/github/repos/')
        self.assertEqual(resp.status_code, 400)
        detail = resp.json()['detail']
        # Error shape per AGENTS.md §1.8: consequence + module/process + cause.
        self.assertIn('Backend.Creators.GithubSync', detail)
        self.assertIn('no GitHub App installation', detail)

    def test_push_endpoint_rejects_when_disconnected(self):
        self._auth()
        resp = self.client_api.post('/api/v1/integrations/github/push/')
        self.assertEqual(resp.status_code, 400)
        self.assertIn('no GitHub App installation', resp.json()['detail'])

    def test_materialize_skips_assets_by_default(self):
        """Without `include_assets`, the export must NOT contain
        any `assets/...` paths even if the user has an avatar."""
        from django.core.files.base import ContentFile
        from creators.services.github_sync import materialize

        self.creator.image.save(
            'avatar.png', ContentFile(b'\x89PNG\r\n\x1a\nfake'),
        )
        self.creator.refresh_from_db()
        files = materialize(self.creator)
        for f in files:
            self.assertFalse(
                f.path.startswith('assets/'),
                msg=f'unexpected asset path in default export: {f.path}',
            )

    def test_materialize_include_assets_inlines_avatar_and_cover(self):
        """With `include_assets=True`, the avatar and any note
        cover_image are read from Django storage and added under
        `assets/`. The manifest's `include_assets` flag flips true."""
        from django.core.files.base import ContentFile
        from courses.models import Course
        from notes.models import Note
        from notechondria.utils import generate_unique_id
        from creators.services.github_sync import materialize

        self.creator.image.save(
            'avatar.png', ContentFile(b'\x89PNG\r\n\x1a\nfake'),
        )
        self.creator.refresh_from_db()
        course = Course.objects.create(
            creator_id=self.creator,
            slug='inbox',
            title='Inbox',
            is_default=True,
        )
        note = Note.objects.create(
            creator_id=self.creator,
            course_id=course,
            sharing_id=generate_unique_id(Note, 'sharing_id'),
            title='Hello',
            content='# hello',
        )
        note.cover_image.save(
            'cover.jpg', ContentFile(b'\xff\xd8\xff\xe0fakejpg'),
        )
        note.refresh_from_db()
        files = materialize(self.creator, include_assets=True)
        paths = {f.path for f in files}
        self.assertIn('assets/avatar.png', paths)
        self.assertIn(f'assets/notes/{note.uuid.hex}/cover.jpg', paths)
        # Manifest should declare the flag so the restore CLI knows
        # whether to look for assets or follow CDN URLs.
        manifest_bytes = next(
            f.content_bytes for f in files if f.path == 'manifest.json'
        )
        manifest = json.loads(manifest_bytes.decode('utf-8'))
        self.assertTrue(manifest['include_assets'])

    def test_materialize_skips_assets_over_per_file_cap(self):
        """A single attachment over `ASSET_FILE_MAX_BYTES` must NOT
        appear in the export; the manifest records the skip with a
        `size_bytes` and `reason` so the operator can audit."""
        from unittest.mock import patch

        from django.core.files.base import ContentFile
        from courses.models import Course
        from notes.models import Note
        from notechondria.utils import generate_unique_id
        from creators.services import github_sync

        course = Course.objects.create(
            creator_id=self.creator, slug='inbox', title='Inbox',
            is_default=True,
        )
        note = Note.objects.create(
            creator_id=self.creator,
            course_id=course,
            sharing_id=generate_unique_id(Note, 'sharing_id'),
            title='Heavy',
            content='heavy',
        )
        note.cover_image.save(
            'big.png', ContentFile(b'X' * 1024),
        )
        note.refresh_from_db()
        # Lower the cap to 100 bytes so the 1 KB cover trips it.
        with patch.object(github_sync, 'ASSET_FILE_MAX_BYTES', 100):
            files = github_sync.materialize(
                self.creator, include_assets=True,
            )
        paths = {f.path for f in files}
        self.assertNotIn(
            f'assets/notes/{note.uuid.hex}/cover.png', paths,
            msg='oversized asset should have been skipped',
        )
        manifest = json.loads(
            next(
                f.content_bytes for f in files if f.path == 'manifest.json'
            ).decode('utf-8'),
        )
        skipped = manifest.get('skipped_assets') or []
        self.assertTrue(
            any(
                entry['path'].endswith(f'/{note.uuid.hex}/cover.png')
                for entry in skipped
            ),
            msg=f'skipped_assets did not record the cover: {skipped!r}',
        )
