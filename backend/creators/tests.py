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


class OrphanAssetPruneTests(TestCase):
    """Pure-function coverage for `_orphan_asset_deletions` (#28): decides
    which `assets/notes/<uuid>/…` blobs to delete on a `prune_orphans`
    push. No DB / no network."""

    def _fn(self):
        from creators.services.github_sync import _orphan_asset_deletions
        return _orphan_asset_deletions

    def _tree(self):
        # `dead` note was deleted client-side; `live` is still present.
        return [
            {'path': 'notes/live.md', 'type': 'blob', 'mode': '100644'},
            {'path': 'assets/avatar.png', 'type': 'blob', 'mode': '100644'},
            {'path': 'assets/notes', 'type': 'tree', 'mode': '040000'},
            {'path': 'assets/notes/live', 'type': 'tree', 'mode': '040000'},
            {'path': 'assets/notes/live/cover.jpg',
             'type': 'blob', 'mode': '100644'},
            {'path': 'assets/notes/dead/cover.png',
             'type': 'blob', 'mode': '100644'},
            {'path': 'assets/notes/dead/attachments/a1.bin',
             'type': 'blob', 'mode': '100644'},
        ]

    def test_deletes_only_dead_note_asset_blobs(self):
        deletions = self._fn()(self._tree(), {'live'})
        paths = {d['path'] for d in deletions}
        self.assertEqual(paths, {
            'assets/notes/dead/cover.png',
            'assets/notes/dead/attachments/a1.bin',
        })
        # Every deletion is a null-sha blob entry (the Git Trees delete form).
        for d in deletions:
            self.assertIsNone(d['sha'])
            self.assertEqual(d['type'], 'blob')
            self.assertEqual(d['mode'], '100644')

    def test_live_assets_avatar_and_notes_are_kept(self):
        deletions = self._fn()(self._tree(), {'live'})
        paths = {d['path'] for d in deletions}
        # A live note's cover, the avatar, notes/, and tree entries survive.
        self.assertNotIn('assets/notes/live/cover.jpg', paths)
        self.assertNotIn('assets/avatar.png', paths)
        self.assertNotIn('notes/live.md', paths)
        # `tree` entries are never emitted as deletions (only blobs).
        self.assertNotIn('assets/notes/dead', paths)

    def test_empty_live_set_prunes_all_note_assets(self):
        deletions = self._fn()(self._tree(), set())
        paths = {d['path'] for d in deletions}
        self.assertEqual(paths, {
            'assets/notes/live/cover.jpg',
            'assets/notes/dead/cover.png',
            'assets/notes/dead/attachments/a1.bin',
        })
        # Non-note assets (avatar) are still never touched.
        self.assertNotIn('assets/avatar.png', paths)

    def test_all_live_prunes_nothing(self):
        deletions = self._fn()(self._tree(), {'live', 'dead'})
        self.assertEqual(deletions, [])


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
        # 0.1.109/0.1.116: signin_url points at the org-themed login
        # page (endpoint + /login/ + org name), not the raw OAuth
        # authorize endpoint.
        self.assertEqual(
            body['signin_url'], 'https://auth.example/login/notechondria',
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

    def test_resolve_user_no_longer_auto_links_by_email(self):
        """0.1.118 retired automatic email adoption: a matching email
        with no `casdoor_sub` link must resolve to None so the
        exchange view mints a LinkChallenge and the user explicitly
        chooses bind-vs-create. (This test asserted the opposite
        before 0.1.127; it had been failing since the 0.1.118
        behavior change.)"""
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
        self.assertIsNone(resolved)
        creator = Creator.objects.get(user_id=existing)
        self.assertEqual(creator.casdoor_sub, '')

    def test_resolve_user_no_longer_auto_provisions(self):
        """0.1.118 retired auto-provisioning: an unknown sub resolves
        to None (LinkChallenge path) instead of creating a User row."""
        from creators.casdoor_auth import _resolve_user
        before = User.objects.count()
        resolved = _resolve_user({
            'id': 'casdoor-uid-2',
            'email': 'fresh@example.com',
            'name': 'fresh',
            'firstName': 'Fresh',
            'lastName': 'User',
        })
        self.assertIsNone(resolved)
        self.assertEqual(User.objects.count(), before)

    def test_resolve_user_fast_path_matches_linked_sub(self):
        from creators.casdoor_auth import _resolve_user
        linked = User.objects.create_user(
            username='linked', email='linked@example.com', password='pw',
        )
        Creator.objects.create(user_id=linked, casdoor_sub='casdoor-uid-3')
        resolved = _resolve_user({'id': 'casdoor-uid-3'})
        self.assertIsNotNone(resolved)
        self.assertEqual(resolved.pk, linked.pk)

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


class CasdoorPasswordClaimsSyncTests(TestCase):
    """Coverage for `creators.casdoor_password.sync_password_from_claims`
    — mirroring Casdoor JWT-Custom credential-hash claims into
    `User.password` for the email/password fallback."""

    def setUp(self):
        self.user = User.objects.create_user(
            username='claims-user',
            email='claims@example.com',
            password='old-local-password',
            is_active=True,
        )

    def test_plain_password_type_sets_local_password(self):
        from creators.casdoor_password import sync_password_from_claims
        changed = sync_password_from_claims(self.user, {
            'password': 'fresh-plaintext',
            'passwordType': 'plain',
        })
        self.assertTrue(changed)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('fresh-plaintext'))
        self.assertFalse(self.user.check_password('old-local-password'))

    def test_bcrypt_password_type_stores_verifiable_hash(self):
        import bcrypt as bcrypt_lib
        from creators.casdoor_password import sync_password_from_claims
        raw_hash = bcrypt_lib.hashpw(
            b'casdoor-bcrypt-pass', bcrypt_lib.gensalt(rounds=4),
        ).decode()
        changed = sync_password_from_claims(self.user, {
            'password': raw_hash,
            'passwordSalt': 'org-salt-ignored-for-bcrypt',
            'passwordType': 'bcrypt',
        })
        self.assertTrue(changed)
        self.user.refresh_from_db()
        self.assertEqual(self.user.password, 'bcrypt$' + raw_hash)
        self.assertTrue(self.user.check_password('casdoor-bcrypt-pass'))

    def test_empty_password_claim_is_dormant(self):
        """Current Casdoor builds scrub the `password` claim value
        (verified against auth.trance-0.com): the sync must be a
        silent no-op, keeping the previously stored local hash."""
        from creators.casdoor_password import sync_password_from_claims
        before = self.user.password
        changed = sync_password_from_claims(self.user, {
            'password': '',
            'passwordSalt': 'org-salt',
            'passwordType': 'bcrypt',
        })
        self.assertFalse(changed)
        self.user.refresh_from_db()
        self.assertEqual(self.user.password, before)
        self.assertTrue(self.user.check_password('old-local-password'))

    def test_unsupported_password_type_is_skipped(self):
        from creators.casdoor_password import sync_password_from_claims
        before = self.user.password
        changed = sync_password_from_claims(self.user, {
            'password': 'deadbeef',
            'passwordType': 'argon2id',
        })
        self.assertFalse(changed)
        self.user.refresh_from_db()
        self.assertEqual(self.user.password, before)


class LoginCasdoorRopcSyncTests(TestCase):
    """Coverage for the fallback login's Casdoor ROPC resync path
    (`LoginSerializer._casdoor_password_sync`)."""

    def setUp(self):
        self.client_api = APIClient()
        self.user = User.objects.create_user(
            username='ropc-user',
            email='ropc@example.com',
            password='stale-local-password',
            is_active=True,
        )
        self.creator = Creator.objects.create(
            user_id=self.user, casdoor_sub='sub-1234',
        )

    def _login(self, password, identifier='ropc@example.com'):
        return self.client_api.post(
            '/api/v1/auth/login/',
            {'email': identifier, 'password': password},
            format='json',
        )

    def test_local_hash_still_wins_without_casdoor(self):
        """Outage shape: ROPC disabled/unreachable — the locally
        stored hash keeps authenticating."""
        resp = self._login('stale-local-password')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['user']['username'], 'ropc-user')

    def test_ropc_success_resyncs_local_password(self):
        from unittest.mock import patch
        with patch(
            'creators.casdoor_password.password_grant',
            return_value=('ok', {'sub': 'sub-1234'}),
        ) as grant:
            resp = self._login('new-casdoor-password')
        self.assertEqual(resp.status_code, 200)
        grant.assert_called()
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('new-casdoor-password'))
        # And the resynced hash now works offline (no mock needed).
        resp2 = self._login('new-casdoor-password')
        self.assertEqual(resp2.status_code, 200)

    def test_ropc_sub_mismatch_is_rejected(self):
        from unittest.mock import patch
        with patch(
            'creators.casdoor_password.password_grant',
            return_value=('ok', {'sub': 'someone-else'}),
        ):
            resp = self._login('new-casdoor-password')
        self.assertEqual(resp.status_code, 400)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('stale-local-password'))

    def test_ropc_unreachable_rejects_unknown_password(self):
        from unittest.mock import patch
        with patch(
            'creators.casdoor_password.password_grant',
            return_value=('unreachable', None),
        ):
            resp = self._login('new-casdoor-password')
        self.assertEqual(resp.status_code, 400)

    def test_unlinked_account_never_calls_casdoor(self):
        from unittest.mock import patch
        self.creator.casdoor_sub = ''
        self.creator.save(update_fields=['casdoor_sub'])
        with patch(
            'creators.casdoor_password.password_grant',
        ) as grant:
            resp = self._login('wrong-password')
        self.assertEqual(resp.status_code, 400)
        grant.assert_not_called()


class LastSeenVersionsTests(TestCase):
    """Coverage for the per-app What's-New tracking field
    (`Creator.last_seen_versions`) on the settings endpoint."""

    def setUp(self):
        self.client_api = APIClient()
        self.user = User.objects.create_user(
            username='versions-user',
            email='versions@example.com',
            password='pw',
            is_active=True,
        )
        self.token = Token.objects.create(user=self.user)

    def _patch(self, payload):
        return self.client_api.patch(
            '/api/v1/settings/',
            payload,
            format='json',
            HTTP_AUTHORIZATION=f'Token {self.token.key}',
        )

    def test_settings_get_defaults_to_empty_map(self):
        resp = self.client_api.get(
            '/api/v1/settings/',
            HTTP_AUTHORIZATION=f'Token {self.token.key}',
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()['last_seen_versions'], {})

    def test_patch_merges_per_app_entries(self):
        resp = self._patch({'last_seen_versions': {'editor': '0.1.127'}})
        self.assertEqual(resp.status_code, 200)
        resp2 = self._patch({'last_seen_versions': {'planner': '0.1.126'}})
        self.assertEqual(resp2.status_code, 200)
        self.assertEqual(
            resp2.json()['last_seen_versions'],
            {'editor': '0.1.127', 'planner': '0.1.126'},
        )
        creator = Creator.objects.get(user_id=self.user)
        self.assertEqual(
            creator.last_seen_versions,
            {'editor': '0.1.127', 'planner': '0.1.126'},
        )

    def test_patch_rejects_non_dict_and_oversized_entries(self):
        resp = self._patch({'last_seen_versions': ['0.1.127']})
        self.assertEqual(resp.status_code, 400)
        resp2 = self._patch({'last_seen_versions': {'x' * 40: '0.1.127'}})
        self.assertEqual(resp2.status_code, 400)
        resp3 = self._patch({'last_seen_versions': {'editor': ''}})
        self.assertEqual(resp3.status_code, 400)


class SeedAgentUserCommandTests(TestCase):
    """The agent-harness seed command: guarded, idempotent, mints a key."""

    def _run(self, **env):
        import io
        from unittest import mock
        from django.core.management import call_command
        out = io.StringIO()
        with mock.patch.dict('os.environ', env, clear=False):
            call_command('seed_agent_user', stdout=out)
        return out.getvalue()

    def test_refuses_without_debug_or_env_flag(self):
        from django.core.management.base import CommandError
        with self.settings(DEBUG=False):
            with self.assertRaises(CommandError) as ctx:
                self._run(ALLOW_AGENT_SEED='')
        self.assertIn('seed_agent_user', str(ctx.exception))

    def test_creates_user_and_prints_key(self):
        with self.settings(DEBUG=True):
            output = self._run()
        self.assertIn('NOTECHONDRIA_API_KEY=ntc_', output)
        user = User.objects.get(username='agent-tester')
        self.assertTrue(user.is_active)
        self.assertFalse(user.has_usable_password())
        creator = Creator.objects.get(user_id=user)
        key = output.rsplit('NOTECHONDRIA_API_KEY=', 1)[1].strip()
        import hashlib
        self.assertEqual(creator.api_key_hash, hashlib.sha256(key.encode()).hexdigest())
        self.assertEqual(creator.api_key_prefix, key[:8])

    def test_rerun_is_idempotent_and_rotates_key(self):
        with self.settings(DEBUG=False):
            out1 = self._run(ALLOW_AGENT_SEED='1')
            out2 = self._run(ALLOW_AGENT_SEED='1')
        key1 = out1.rsplit('NOTECHONDRIA_API_KEY=', 1)[1].strip()
        key2 = out2.rsplit('NOTECHONDRIA_API_KEY=', 1)[1].strip()
        self.assertNotEqual(key1, key2)
        self.assertEqual(User.objects.filter(username='agent-tester').count(), 1)
        self.assertIn('reused', out2)


class CasdoorAvatarClaimSyncTests(TestCase):
    """The Casdoor JWT avatar sync: reads the standard OIDC `picture`
    claim as a fallback for the custom `avatar` field, and stores it on
    `Creator.avatar_url` (0.1.163)."""

    def setUp(self):
        from creators.utils import ensure_creator
        self.user = User.objects.create_user(
            username='avatar-user', email='av@example.com', is_active=True,
        )
        self.creator = ensure_creator(self.user)

    def test_avatar_claim_preferred_when_present(self):
        from creators.casdoor_auth import _sync_creator_from_claims
        _sync_creator_from_claims(self.creator, {
            'avatar': 'https://cas/av.png',
            'picture': 'https://cas/pic.png',
        })
        self.creator.refresh_from_db()
        self.assertEqual(self.creator.avatar_url, 'https://cas/av.png')

    def test_picture_claim_used_when_avatar_absent(self):
        # Casdoor tokens carry the standard OIDC `picture` by default;
        # the custom `avatar` field is only present if the operator
        # enabled it. The sync must still resolve an avatar.
        from creators.casdoor_auth import _sync_creator_from_claims
        _sync_creator_from_claims(self.creator, {
            'picture': 'https://cas/pic.png',
        })
        self.creator.refresh_from_db()
        self.assertEqual(self.creator.avatar_url, 'https://cas/pic.png')

    def test_settings_payload_exposes_local_upload_separately(self):
        from rest_framework.test import APIClient
        from rest_framework.authtoken.models import Token
        # avatar_url set (as if from Casdoor) but no local upload.
        self.creator.avatar_url = 'https://cas/pic.png'
        self.creator.save(update_fields=['avatar_url'])
        token = Token.objects.create(user=self.user)
        client = APIClient()
        resp = client.get(
            '/api/v1/settings/', HTTP_AUTHORIZATION=f'Token {token.key}',
        )
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        # image_url is the effective avatar (Casdoor wins); image_upload_url
        # is exposed separately so the SPA can fall back to the local image
        # (here the default profile image `ensure_creator` attaches) when the
        # Casdoor avatar fails to load.
        self.assertEqual(body['avatar_url'], 'https://cas/pic.png')
        self.assertEqual(body['image_url'], 'https://cas/pic.png')
        self.assertIn('image_upload_url', body)
        # A local image always exists (default attached at creator creation),
        # and it is distinct from the Casdoor avatar_url.
        self.assertTrue(body['image_upload_url'])
        self.assertNotEqual(body['image_upload_url'], body['avatar_url'])
        self.assertIn('/media/', body['image_upload_url'])


class AvatarMirrorTests(TestCase):
    """0.1.184: Casdoor avatars are mirrored into our storage on login
    (Casdoor serves without CORS headers → Flutter web can't render
    them), and payloads prefer the mirrored copy."""

    def setUp(self):
        from django.contrib.auth.models import User as U
        self.user = U.objects.create_user(username='mirror@example.com', password='pw')
        from creators.models import Creator as C
        self.creator = C.objects.create(user_id=self.user)
        self.creator.avatar_url = 'https://cas.example.com/avatar/me.png'
        self.creator.save(update_fields=['avatar_url'])

    def _fake_resp(self, status=200, content=b'\x89PNG fake', ctype='image/png'):
        class R:
            status_code = status
            headers = {'content-type': ctype}
        R.content = content
        return R()

    def test_mirror_stores_bytes_and_records_source(self):
        from unittest.mock import patch
        from creators.utils import mirror_remote_avatar

        with patch('requests.get', return_value=self._fake_resp()):
            stored = mirror_remote_avatar(self.creator)
        self.assertTrue(stored)
        self.creator.refresh_from_db()
        self.assertEqual(
            self.creator.avatar_mirrored_from,
            'https://cas.example.com/avatar/me.png',
        )
        # The image field's upload_to callable renames files (profile_latest_*),
        # so assert on WHERE it landed (our storage), not the filename.
        self.assertTrue(self.creator.image.name)
        self.assertIn('user_upload', self.creator.image.name)

    def test_mirror_is_idempotent_per_url(self):
        from unittest.mock import patch
        from creators.utils import mirror_remote_avatar

        with patch('requests.get', return_value=self._fake_resp()) as m:
            self.assertTrue(mirror_remote_avatar(self.creator))
            self.assertFalse(mirror_remote_avatar(self.creator))
            self.assertEqual(m.call_count, 1)

    def test_mirror_rejects_non_image(self):
        from unittest.mock import patch
        from creators.utils import mirror_remote_avatar

        with patch('requests.get',
                   return_value=self._fake_resp(ctype='text/html')):
            self.assertFalse(mirror_remote_avatar(self.creator))
        self.creator.refresh_from_db()
        self.assertEqual(self.creator.avatar_mirrored_from, '')

    def test_payload_prefers_mirrored_copy(self):
        from unittest.mock import patch
        from creators.utils import mirror_remote_avatar
        from notes.api import creator_summary_payload

        with patch('requests.get', return_value=self._fake_resp()):
            mirror_remote_avatar(self.creator)
        self.creator.refresh_from_db()
        payload = creator_summary_payload(self.creator, None)
        # Effective avatar = our stored media (CORS-safe), not the IdP URL.
        self.assertIn('/media/', payload['image_url'])
        self.assertFalse(
            payload['image_url'].startswith('https://cas.example.com/'))
        self.assertTrue(
            payload['avatar_url'].startswith('https://cas.example.com/'))

    def test_payload_falls_back_to_casdoor_url_without_mirror(self):
        from notes.api import creator_summary_payload

        payload = creator_summary_payload(self.creator, None)
        self.assertTrue(
            payload['image_url'].startswith('https://cas.example.com/'))


class GithubSyncPushConflictTests(TestCase):
    """0.1.189: the profile-sync push is one atomic Git Data commit and
    refuses to overwrite a branch that moved since our last push."""

    def setUp(self):
        from django.contrib.auth.models import User as U
        from creators.models import Creator as C, GithubIntegration
        self.user = U.objects.create_user(username='sync@example.com', password='pw')
        self.creator = C.objects.create(user_id=self.user)
        self.integration = GithubIntegration.objects.create(
            creator=self.creator, installation_id='inst-sync',
            repo_full_name='octo/backup', repo_default_branch='main',
        )

    def _files(self):
        from creators.services.github_sync import _RepoFile
        return [_RepoFile('profile/creator.json', b'{"a":1}')]

    def _fake_transport(self, head_sha, tree_sha='newtree'):
        """Minimal Git Data API double; records the calls it receives."""
        calls = {'posts': [], 'patches': []}

        class R:
            def __init__(self, payload, status=200):
                self._p, self.status_code, self.text = payload, status, ''
            def json(self): return self._p

        def get(url, headers=None, timeout=None, params=None):
            if '/git/ref/heads/' in url:
                return R({'object': {'sha': head_sha}})
            if '/git/commits/' in url:
                return R({'tree': {'sha': 'basetree'}})
            return R({}, 404)

        def post(url, headers=None, json=None, timeout=None):
            calls['posts'].append(url)
            if url.endswith('/git/blobs'):
                return R({'sha': 'blob1'})
            if url.endswith('/git/trees'):
                return R({'sha': tree_sha})
            if url.endswith('/git/commits'):
                return R({'sha': 'commit-new'})
            return R({}, 404)

        def patch(url, headers=None, json=None, timeout=None):
            calls['patches'].append(url)
            return R({})

        return get, post, patch, calls

    def test_conflict_when_remote_moved_since_last_push(self):
        from unittest.mock import patch as mpatch
        from creators.services.github_sync import commit_and_push, GithubSyncConflict

        self.integration.last_push_sha = 'ours-old'
        self.integration.save(update_fields=['last_push_sha'])
        get, post, patch_, calls = self._fake_transport(head_sha='someone-else')
        with mpatch('creators.services.github_sync._ensure_token', return_value='t'), \
             mpatch('requests.get', get), mpatch('requests.post', post), \
             mpatch('requests.patch', patch_):
            with self.assertRaises(GithubSyncConflict):
                commit_and_push(self.integration, self._files())
        # Nothing was written.
        self.assertEqual(calls['patches'], [])

    def test_force_overwrites_a_moved_branch(self):
        from unittest.mock import patch as mpatch
        from creators.services.github_sync import commit_and_push

        self.integration.last_push_sha = 'ours-old'
        self.integration.save(update_fields=['last_push_sha'])
        get, post, patch_, calls = self._fake_transport(head_sha='someone-else')
        with mpatch('creators.services.github_sync._ensure_token', return_value='t'), \
             mpatch('requests.get', get), mpatch('requests.post', post), \
             mpatch('requests.patch', patch_):
            sha = commit_and_push(self.integration, self._files(), force=True)
        self.assertEqual(sha, 'commit-new')
        self.assertEqual(len(calls['patches']), 1)

    def test_first_ever_push_has_nothing_to_conflict_with(self):
        from unittest.mock import patch as mpatch
        from creators.services.github_sync import commit_and_push

        self.assertEqual(self.integration.last_push_sha, '')
        get, post, patch_, calls = self._fake_transport(head_sha='whatever')
        with mpatch('creators.services.github_sync._ensure_token', return_value='t'), \
             mpatch('requests.get', get), mpatch('requests.post', post), \
             mpatch('requests.patch', patch_):
            sha = commit_and_push(self.integration, self._files())
        self.assertEqual(sha, 'commit-new')

    def test_single_atomic_commit_not_per_file_writes(self):
        from unittest.mock import patch as mpatch
        from creators.services.github_sync import commit_and_push, _RepoFile

        files = [_RepoFile(f'notes/{i}.md', b'x') for i in range(12)]
        get, post, patch_, calls = self._fake_transport(head_sha='head')
        with mpatch('creators.services.github_sync._ensure_token', return_value='t'), \
             mpatch('requests.get', get), mpatch('requests.post', post), \
             mpatch('requests.patch', patch_):
            commit_and_push(self.integration, files)
        trees = [u for u in calls['posts'] if u.endswith('/git/trees')]
        commits = [u for u in calls['posts'] if u.endswith('/git/commits')]
        # 12 files → exactly one tree, one commit, one ref update.
        self.assertEqual(len(trees), 1)
        self.assertEqual(len(commits), 1)
        self.assertEqual(len(calls['patches']), 1)

    def test_unchanged_tree_makes_no_commit(self):
        from unittest.mock import patch as mpatch
        from creators.services.github_sync import commit_and_push

        # Tree resolves to the SAME sha as the base tree → nothing to do.
        get, post, patch_, calls = self._fake_transport(
            head_sha='head', tree_sha='basetree')
        with mpatch('creators.services.github_sync._ensure_token', return_value='t'), \
             mpatch('requests.get', get), mpatch('requests.post', post), \
             mpatch('requests.patch', patch_):
            sha = commit_and_push(self.integration, self._files())
        self.assertEqual(sha, 'head')
        self.assertEqual(calls['patches'], [])
        self.assertNotIn(
            f'{"https://api.github.com"}/repos/octo/backup/git/commits',
            calls['posts'])
