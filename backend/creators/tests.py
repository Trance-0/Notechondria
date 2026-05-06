import json
from datetime import datetime, timezone as dt_timezone

from django.contrib.auth.models import User
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from .models import Creator, user_profile_path


class CreatorModelTests(TestCase):
    def test_user_profile_path_uses_stable_filename(self):
        user = User.objects.create_user(username='alice', password='pw')
        creator = Creator.objects.create(user_id=user)

        path = user_profile_path(creator, 'portrait.png')

        self.assertEqual(path, f'user_upload/user_{user.id}/profile_pic/profile_latest.png')


class SettingsApiTests(TestCase):
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
        token = Token.objects.create(user=self.user)
        self.client_api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

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


class CasdoorAuthTests(TestCase):
    """Coverage for the Casdoor surface (`creators.casdoor_auth`,
    `CasdoorConfigApiView`, `CasdoorExchangeApiView`,
    `CasdoorBindApiView`, `CasdoorUnlinkApiView`)."""

    def setUp(self):
        self.client_api = APIClient()

    def test_config_view_reports_unconfigured_in_shadow_mode(self):
        """When CASDOOR_* env vars are unset, the config endpoint
        must return `{configured: false}` so the SPA can show a
        "Casdoor not configured" hint."""
        from django.test import override_settings
        with override_settings(
            CASDOOR_ENDPOINT='', CASDOOR_CLIENT_ID='',
            CASDOOR_ORG_NAME='', CASDOOR_APP_NAME='',
        ):
            resp = self.client_api.get('/api/v1/auth/casdoor/config/')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), {'configured': False})

    def test_config_view_returns_oauth_targets_when_configured(self):
        from django.test import override_settings
        with override_settings(
            CASDOOR_ENDPOINT='https://auth.example/',
            CASDOOR_CLIENT_ID='client-abc',
            CASDOOR_CLIENT_SECRET='shh',
            CASDOOR_ORG_NAME='notechondria',
            CASDOOR_APP_NAME='notechondria',
            CASDOOR_CERTIFICATE='---PEM---',
        ):
            resp = self.client_api.get('/api/v1/auth/casdoor/config/')
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertTrue(body['configured'])
        self.assertEqual(body['client_id'], 'client-abc')
        self.assertEqual(body['organization'], 'notechondria')
        self.assertEqual(
            body['signin_url'], 'https://auth.example/login/oauth/authorize',
        )

    def test_exchange_endpoint_returns_503_in_shadow_mode(self):
        from django.test import override_settings
        with override_settings(
            CASDOOR_ENDPOINT='', CASDOOR_CLIENT_ID='',
        ):
            resp = self.client_api.post(
                '/api/v1/auth/casdoor/exchange/',
                {'code': 'irrelevant'}, format='json',
            )
        self.assertEqual(resp.status_code, 503)
        self.assertIn('shadow mode', resp.json()['detail'])

    def test_jwt_auth_class_is_noop_when_not_configured(self):
        """The DRF authentication class must return None (silently)
        when CASDOOR_* env vars aren't set, so other auth backends
        can still match the same Bearer header."""
        from creators.casdoor_auth import (
            CasdoorJWTAuthentication,
            _build_sdk,
        )
        # Reset module cache between tests; settings overrides don't
        # invalidate _cached_sdk on their own.
        import creators.casdoor_auth as ca
        ca._cached_sdk = None
        ca._cached_sdk_signature = ()

        from django.test import override_settings, RequestFactory
        rf = RequestFactory()
        with override_settings(CASDOOR_ENDPOINT=''):
            self.assertIsNone(_build_sdk())
            req = rf.get(
                '/', HTTP_AUTHORIZATION='Bearer some.jwt.value',
            )
            self.assertIsNone(CasdoorJWTAuthentication().authenticate(req))

    def test_jwt_auth_class_skips_mcp_keys(self):
        """A `Bearer ntc_<key>` header must be handed off to the next
        auth class — Casdoor only owns OAuth JWTs, not MCP keys."""
        from creators.casdoor_auth import CasdoorJWTAuthentication
        import creators.casdoor_auth as ca
        ca._cached_sdk = None
        ca._cached_sdk_signature = ()

        from django.test import override_settings, RequestFactory
        rf = RequestFactory()
        with override_settings(
            CASDOOR_ENDPOINT='https://auth.example',
            CASDOOR_CLIENT_ID='c',
            CASDOOR_CLIENT_SECRET='s',
            CASDOOR_ORG_NAME='o',
            CASDOOR_APP_NAME='a',
            CASDOOR_CERTIFICATE='dummy',
        ):
            req = rf.get(
                '/', HTTP_AUTHORIZATION='Bearer ntc_abcdef0123456789',
            )
            self.assertIsNone(CasdoorJWTAuthentication().authenticate(req))

    def test_resolve_user_links_existing_account_by_email(self):
        """An existing legacy account (no `casdoor_sub`) should adopt
        the link automatically when its email matches the JWT claim,
        instead of getting a duplicate."""
        from creators.casdoor_auth import _resolve_user
        existing = User.objects.create_user(
            username='legacy', email='legacy@example.com', password='pw',
        )
        Creator.objects.create(user_id=existing)
        resolved = _resolve_user({
            'id': 'casdoor-uid-1',
            'email': 'legacy@example.com',
            'name': 'legacy-from-casdoor',
        })
        self.assertEqual(resolved.pk, existing.pk)
        # Backfill must persist so the second call hits the fast path.
        creator = Creator.objects.get(user_id=existing)
        self.assertEqual(creator.casdoor_sub, 'casdoor-uid-1')

    def test_resolve_user_auto_provisions_when_no_match(self):
        from creators.casdoor_auth import _resolve_user
        before = User.objects.count()
        resolved = _resolve_user({
            'id': 'casdoor-uid-2',
            'email': 'fresh@example.com',
            'name': 'fresh',
            'firstName': 'Fresh',
            'lastName': 'User',
        })
        self.assertIsNotNone(resolved)
        self.assertEqual(User.objects.count(), before + 1)
        self.assertEqual(resolved.email, 'fresh@example.com')
        self.assertEqual(resolved.first_name, 'Fresh')
        creator = Creator.objects.get(user_id=resolved)
        self.assertEqual(creator.casdoor_sub, 'casdoor-uid-2')

    def test_resolve_user_returns_none_without_sub(self):
        from creators.casdoor_auth import _resolve_user
        self.assertIsNone(_resolve_user({'email': 'noid@example.com'}))

    def test_bind_endpoint_requires_auth(self):
        resp = self.client_api.post(
            '/api/v1/auth/casdoor/bind/',
            {'code': 'irrelevant'}, format='json',
        )
        self.assertIn(resp.status_code, (401, 403))

    def test_bind_endpoint_returns_503_in_shadow_mode(self):
        from django.test import override_settings
        u = User.objects.create_user(username='ub', password='pw')
        Creator.objects.create(user_id=u)
        token = Token.objects.create(user=u)
        self.client_api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')
        with override_settings(CASDOOR_ENDPOINT=''):
            resp = self.client_api.post(
                '/api/v1/auth/casdoor/bind/',
                {'code': 'x'}, format='json',
            )
        self.assertEqual(resp.status_code, 503)
        self.assertIn('shadow mode', resp.json()['detail'])

    def test_bind_endpoint_rejects_conflicting_sub(self):
        """If the Casdoor sub is already on another Creator, the bind
        must return 409 instead of silently transferring the link."""
        from unittest.mock import patch
        from django.test import override_settings

        # User A already linked to sub `casdoor-uid-99`.
        a = User.objects.create_user(username='a', email='a@x.com', password='pw')
        Creator.objects.create(user_id=a, casdoor_sub='casdoor-uid-99')

        # User B is signed in and tries to bind the same sub.
        b = User.objects.create_user(username='b', email='b@x.com', password='pw')
        Creator.objects.create(user_id=b)
        token = Token.objects.create(user=b)
        self.client_api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        with override_settings(
            CASDOOR_ENDPOINT='https://auth.example',
            CASDOOR_CLIENT_ID='c',
            CASDOOR_CLIENT_SECRET='s',
            CASDOOR_ORG_NAME='o',
            CASDOOR_APP_NAME='ap',
            CASDOOR_CERTIFICATE='dummy',
        ), patch(
            'creators.casdoor_auth._build_sdk',
        ) as mock_sdk_factory, patch(
            'creators.casdoor_auth.verify_token',
            return_value={'id': 'casdoor-uid-99', 'email': 'a@x.com'},
        ):
            mock_sdk = mock_sdk_factory.return_value
            mock_sdk.get_oauth_token.return_value = {
                'access_token': 'fake.jwt.value',
            }
            resp = self.client_api.post(
                '/api/v1/auth/casdoor/bind/',
                {'code': 'codez'}, format='json',
            )
        self.assertEqual(resp.status_code, 409)
        self.assertIn('already linked', resp.json()['detail'])
        # User B's casdoor_sub must remain empty after the rejected bind.
        b_creator = Creator.objects.get(user_id=b)
        self.assertEqual(b_creator.casdoor_sub, '')

    def test_bind_endpoint_happy_path_persists_link(self):
        from unittest.mock import patch
        from django.test import override_settings

        u = User.objects.create_user(username='happy', email='h@x.com', password='pw')
        Creator.objects.create(user_id=u)
        token = Token.objects.create(user=u)
        self.client_api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        with override_settings(
            CASDOOR_ENDPOINT='https://auth.example',
            CASDOOR_CLIENT_ID='c',
            CASDOOR_CLIENT_SECRET='s',
            CASDOOR_ORG_NAME='o',
            CASDOOR_APP_NAME='ap',
            CASDOOR_CERTIFICATE='dummy',
        ), patch(
            'creators.casdoor_auth._build_sdk',
        ) as mock_sdk_factory, patch(
            'creators.casdoor_auth.verify_token',
            return_value={'id': 'casdoor-uid-new', 'email': 'h@x.com'},
        ):
            mock_sdk = mock_sdk_factory.return_value
            mock_sdk.get_oauth_token.return_value = {
                'access_token': 'fake.jwt.value',
            }
            resp = self.client_api.post(
                '/api/v1/auth/casdoor/bind/',
                {'code': 'codez'}, format='json',
            )
        self.assertEqual(resp.status_code, 200)
        # Standard auth_payload must include token + user fields.
        body = resp.json()
        self.assertIn('token', body)
        self.assertIn('user', body)
        # And the link must persist.
        creator = Creator.objects.get(user_id=u)
        self.assertEqual(creator.casdoor_sub, 'casdoor-uid-new')

    def test_unlink_endpoint_clears_sub(self):
        u = User.objects.create_user(username='unlinker', password='pw')
        Creator.objects.create(user_id=u, casdoor_sub='casdoor-uid-old')
        token = Token.objects.create(user=u)
        self.client_api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')

        resp = self.client_api.delete('/api/v1/auth/casdoor/unlink/')
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertFalse(body['casdoor_linked'])
        self.assertTrue(body['was_linked'])
        creator = Creator.objects.get(user_id=u)
        self.assertEqual(creator.casdoor_sub, '')

    def test_unlink_endpoint_idempotent(self):
        u = User.objects.create_user(username='unlinker2', password='pw')
        Creator.objects.create(user_id=u)
        token = Token.objects.create(user=u)
        self.client_api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')
        resp = self.client_api.delete('/api/v1/auth/casdoor/unlink/')
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(resp.json()['was_linked'])

    def test_settings_payload_exposes_casdoor_linked(self):
        from creators.api import SettingsSerializer
        u = User.objects.create_user(username='settings-user', password='pw')
        c = Creator.objects.create(user_id=u, casdoor_sub='abc')
        body = SettingsSerializer(c).to_representation(c)
        self.assertTrue(body['casdoor_linked'])
        c.casdoor_sub = ''
        c.save(update_fields=['casdoor_sub'])
        body = SettingsSerializer(c).to_representation(c)
        self.assertFalse(body['casdoor_linked'])
