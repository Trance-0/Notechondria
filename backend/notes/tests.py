import json
from datetime import datetime, time, timedelta, timezone as dt_timezone

from django.contrib.auth.models import User
from django.utils import timezone
from django.test import Client, RequestFactory, TestCase
from django.contrib.messages.storage.fallback import FallbackStorage
from rest_framework.authtoken.models import Token

from creators.models import Creator
from notechondria.utils import check_is_creator, generate_unique_id, get_object_or_None
from .models import (
    CalendarFeed,
    Course,
    CourseOperationLog,
    CourseOperationTypeChoices,
    CourseSubscription,
    HeatmapActivity,
    Note,
    NoteActivitySession,
    NoteBlock,
    NoteBlockTypeChoices,
    NoteVersion,
    PlannerEvent,
    RecycleBinEntry,
)
from .services import (
    normalize_calendar_url,
    parse_ical_datetime,
    seed_inbox_and_welcome_note,
)


class NoteBlockMarkdownTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='bob', password='pw')
        self.creator = Creator.objects.create(user_id=self.user)
        self.course = Course.objects.create(creator_id=self.creator, slug='course-bob', title='Course Bob')
        self.note = Note.objects.create(creator_id=self.creator, course_id=self.course, sharing_id='share1234', title='t')

    def test_code_block_markdown_render(self):
        block = NoteBlock.objects.create(
            creator_id=self.creator,
            note_id=self.note,
            block_type=NoteBlockTypeChoices.CODE,
            args='python',
            text='print("hello")',
            is_AI_generated=False,
        )

        self.assertEqual(block.get_md_str(), '```python\nprint("hello")\n```')

    def test_quote_markdown_render_without_citation(self):
        block = NoteBlock.objects.create(
            creator_id=self.creator,
            note_id=self.note,
            block_type=NoteBlockTypeChoices.QUOTE,
            text='line 1\nline 2',
            is_AI_generated=False,
        )

        self.assertEqual(block.get_md_str(), '> line 1\n> line 2')


class NoteUtilitiesTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='owner', password='pw')
        self.other_user = User.objects.create_user(username='other', password='pw')
        self.creator = Creator.objects.create(user_id=self.user)
        self.other_creator = Creator.objects.create(user_id=self.other_user)
        self.course = Course.objects.create(creator_id=self.creator, slug='course-owner', title='Course Owner')
        self.note = Note.objects.create(creator_id=self.creator, course_id=self.course, sharing_id='shareA123', title='Title')

    def _attach_messages(self, request):
        setattr(request, 'session', self.client.session)
        messages = FallbackStorage(request)
        setattr(request, '_messages', messages)

    def test_get_object_or_none_returns_none_on_missing(self):
        self.assertIsNone(get_object_or_None(Note, pk=999999))

    def test_generate_unique_id_creates_expected_length(self):
        unique_id = generate_unique_id(Note, 'sharing_id', length=12)

        self.assertEqual(len(unique_id), 12)

    def test_check_is_creator_rejects_non_owner(self):
        factory = RequestFactory()
        request = factory.get('/')
        request.user = self.other_user
        self._attach_messages(request)

        owner, instance = check_is_creator(request, Note, id=self.note.id)

        self.assertIsNone(owner)
        self.assertIsNone(instance)


class NotesViewSmokeTests(TestCase):
    def setUp(self):
        self.client = Client()
        self.user = User.objects.create_user(username='viewer', password='pw')
        self.creator = Creator.objects.create(user_id=self.user)

    def test_list_notes_requires_login(self):
        response = self.client.get('/notes/collections/')
        self.assertEqual(response.status_code, 302)

    def test_create_note_form_for_logged_user(self):
        self.client.login(username='viewer', password='pw')
        response = self.client.get('/notes/notes/new')
        self.assertEqual(response.status_code, 200)


class HeatmapApiTests(TestCase):
    def setUp(self):
        self.client = Client()
        self.user = User.objects.create_user(username='heatmap@example.com', password='pw')
        self.creator = Creator.objects.create(user_id=self.user)
        self.course = Course.objects.create(
            creator_id=self.creator,
            slug='heatmap-course',
            title='Heatmap Course',
        )
        self.note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='heatmap-share',
            title='Heatmap Note',
        )
        self.token = Token.objects.create(user=self.user)

    def _auth_headers(self):
        return {'HTTP_AUTHORIZATION': f'Token {self.token.key}'}

    def test_heatmap_endpoint_contains_past_and_future_values(self):
        HeatmapActivity.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            note_id=self.note,
            activity_type='C',
            word_count=320,
        )
        PlannerEvent.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            title='Demo event',
            event_date=timezone.localdate() + timedelta(days=2),
            difficulty_weight=3,
        )

        response = self.client.get('/api/v1/heatmap/', **self._auth_headers())

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        today_cell = next(cell for cell in payload['cells'] if cell['is_today'])
        self.assertIn('past_value', today_cell)
        self.assertEqual(today_cell['past_value'], 3)
        future_cell = next(
            cell for cell in payload['cells']
            if cell['date'] == (timezone.localdate() + timedelta(days=2)).isoformat()
        )
        self.assertEqual(future_cell['future_value'], 3)

    def test_planner_event_create_endpoint(self):
        starts_at = timezone.now().replace(hour=14, minute=0, second=0, microsecond=0) + timedelta(days=1)
        response = self.client.post(
            '/api/v1/planner-events/',
            data=json.dumps({
                'title': 'Review sprint',
                'event_date': (timezone.localdate() + timedelta(days=1)).isoformat(),
                'starts_at': starts_at.isoformat(),
                'ends_at': (starts_at + timedelta(hours=2)).isoformat(),
                'difficulty_weight': 2,
                'course_id': self.course.id,
            }),
            content_type='application/json',
            **self._auth_headers(),
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(PlannerEvent.objects.count(), 1)
        self.assertEqual(response.json()['starts_at'][:13], starts_at.isoformat()[:13])

    def test_note_history_snapshot_and_restore(self):
        self.note.content = '# Original\n\nOne'
        self.note.save()

        snapshot_response = self.client.post(
            f'/api/v1/notes/{self.note.id}/snapshot/',
            data=json.dumps({'reason': 'quit'}),
            content_type='application/json',
            **self._auth_headers(),
        )
        self.assertEqual(snapshot_response.status_code, 201)
        version_id = snapshot_response.json()['id']

        patch_response = self.client.patch(
            f'/api/v1/notes/{self.note.id}/',
            data=json.dumps({'content': '# Updated\n\nTwo'}),
            content_type='application/json',
            **self._auth_headers(),
        )
        self.assertEqual(patch_response.status_code, 200)

        restore_response = self.client.post(
            f'/api/v1/notes/{self.note.id}/restore/{version_id}/',
            data=json.dumps({}),
            content_type='application/json',
            **self._auth_headers(),
        )
        self.assertEqual(restore_response.status_code, 200)
        self.note.refresh_from_db()
        self.assertIn('Original', self.note.content)
        self.assertGreaterEqual(NoteVersion.objects.count(), 2)

    def test_calendar_feed_and_week_activity(self):
        week_start = timezone.localdate()
        starts_at = datetime.combine(
            week_start + timedelta(days=1),
            time(hour=15, minute=0),
            tzinfo=dt_timezone.utc,
        )
        response = self.client.post(
            '/api/v1/calendar-feeds/',
            data=json.dumps({
                'title': 'Imported Calendar',
                'source_kind': 'I',
                'raw_ical': (
                    'BEGIN:VCALENDAR\n'
                    'BEGIN:VEVENT\n'
                    f'DTSTART:{starts_at.strftime("%Y%m%dT%H%M%SZ")}\n'
                    'SUMMARY:Study block\n'
                    'END:VEVENT\n'
                    'END:VCALENDAR'
                ),
                'course_id': self.course.id,
            }),
            content_type='application/json',
            **self._auth_headers(),
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(CalendarFeed.objects.count(), 1)

        week_response = self.client.get(
            f'/api/v1/activity/week/?start_date={week_start.isoformat()}',
            **self._auth_headers(),
        )
        self.assertEqual(week_response.status_code, 200)
        payload = week_response.json()
        self.assertEqual(len(payload['days']), 7)
        self.assertTrue(any(day['events'] for day in payload['days']))

    def test_notes_list_anonymous_returns_public_only(self):
        Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='anon-pub',
            title='Public Anon',
            is_public=True,
        )
        Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='anon-priv',
            title='Private Anon',
            is_public=False,
        )
        response = self.client.get('/api/v1/notes/')

        self.assertEqual(response.status_code, 200)
        titles = [row['title'] for row in response.json()]
        self.assertIn('Public Anon', titles)
        self.assertNotIn('Private Anon', titles)

    def test_authenticated_notes_list_excludes_deleted_and_other_users_notes(self):
        other_user = User.objects.create_user(username='outside', password='pw')
        other_creator = Creator.objects.create(user_id=other_user)
        active_note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='active-share',
            title='Active note',
            content='# Active note\n\nVisible.',
        )
        deleted_note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='deleted-share',
            title='Deleted note',
            content='# Deleted note\n\nHidden.',
            deleted_at=timezone.now(),
        )
        Note.objects.create(
            creator_id=other_creator,
            course_id=self.course,
            sharing_id='other-share',
            title='Other note',
            content='# Other note\n\nHidden.',
        )

        response = self.client.get('/api/v1/notes/', **self._auth_headers())

        self.assertEqual(response.status_code, 200)
        titles = [row['title'] for row in response.json()]
        self.assertIn(active_note.title, titles)
        self.assertNotIn(deleted_note.title, titles)
        self.assertNotIn('Other note', titles)

    def test_note_session_create_and_week_payload(self):
        starts_at = timezone.now().replace(hour=14, minute=0, second=0, microsecond=0)
        response = self.client.post(
            '/api/v1/note-sessions/',
            data=json.dumps({
                'note_id': self.note.id,
                'title': self.note.title,
                'summary': 'Writing summary',
                'started_at': starts_at.isoformat(),
                'ended_at': (starts_at + timedelta(hours=1)).isoformat(),
            }),
            content_type='application/json',
            **self._auth_headers(),
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(NoteActivitySession.objects.count(), 1)

        week_response = self.client.get(
            f'/api/v1/activity/week/?start_date={timezone.localdate().isoformat()}',
            **self._auth_headers(),
        )
        self.assertEqual(week_response.status_code, 200)
        events = [event for day in week_response.json()['days'] for event in day['events']]
        self.assertTrue(any(event['kind'] == 'note_session' for event in events))

    def test_front_page_recommendations_only_return_public_notes(self):
        Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='front-public',
            title='Front public',
            is_public=True,
            content='# Front public\n\nVisible on front page.',
        )
        Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='front-private',
            title='Front private',
            is_public=False,
            content='# Front private\n\nShould stay hidden.',
        )

        response = self.client.get('/api/v1/front-page/')

        self.assertEqual(response.status_code, 200)
        titles = [row['title'] for row in response.json()['recommended_notes']]
        self.assertIn('Front public', titles)
        self.assertNotIn('Front private', titles)

    def test_note_delete_restore_and_empty_recycle_bin(self):
        note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='trash-share',
            title='Trash me',
            content='# Trash me\n\nSoon deleted.',
        )

        delete_response = self.client.delete(
            f'/api/v1/notes/{note.id}/',
            **self._auth_headers(),
        )
        self.assertEqual(delete_response.status_code, 204)
        note.refresh_from_db()
        self.assertIsNotNone(note.deleted_at)
        self.assertEqual(
            RecycleBinEntry.objects.filter(creator_id=self.creator, note_id=note).count(),
            1,
        )

        deleted_response = self.client.get(
            '/api/v1/notes/deleted/',
            **self._auth_headers(),
        )
        self.assertEqual(deleted_response.status_code, 200)
        self.assertEqual([row['title'] for row in deleted_response.json()], ['Trash me'])

        restore_response = self.client.post(
            f'/api/v1/notes/{note.id}/restore/',
            data=json.dumps({}),
            content_type='application/json',
            **self._auth_headers(),
        )
        self.assertEqual(restore_response.status_code, 200)
        note.refresh_from_db()
        self.assertIsNone(note.deleted_at)
        self.assertFalse(
            RecycleBinEntry.objects.filter(creator_id=self.creator, note_id=note).exists()
        )

        self.client.delete(f'/api/v1/notes/{note.id}/', **self._auth_headers())
        empty_response = self.client.delete(
            '/api/v1/notes/deleted/empty/',
            **self._auth_headers(),
        )
        self.assertEqual(empty_response.status_code, 200)
        self.assertEqual(empty_response.json()['count'], 1)
        self.assertFalse(Note.objects.filter(id=note.id).exists())
        self.assertFalse(RecycleBinEntry.objects.filter(creator_id=self.creator).exists())

    def test_note_create_is_idempotent_for_client_draft_id(self):
        payload = {
            'title': 'Draft sync',
            'description': 'Synced from local draft',
            'content': '# Draft sync\n\nFirst upload.',
            'client_draft_id': 'draft-abc',
            'metadata_json': json.dumps({'section': 'one'}),
        }

        first_response = self.client.post(
            '/api/v1/notes/',
            data=json.dumps(payload),
            content_type='application/json',
            **self._auth_headers(),
        )
        second_response = self.client.post(
            '/api/v1/notes/',
            data=json.dumps(payload),
            content_type='application/json',
            **self._auth_headers(),
        )

        self.assertEqual(first_response.status_code, 201)
        self.assertEqual(second_response.status_code, 200)
        self.assertEqual(first_response.json()['id'], second_response.json()['id'])
        self.assertEqual(
            Note.objects.filter(creator_id=self.creator, client_draft_id='draft-abc').count(),
            1,
        )

    def test_note_search_supports_keyword_and_fuzzy_matching(self):
        Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='search-share',
            title='Meaningful Structures',
            content='# Meaningful Structures\n\nKeyword and fuzzy match target.',
        )

        response = self.client.get(
            '/api/v1/notes/?q=meanng strctres',
            **self._auth_headers(),
        )

        self.assertEqual(response.status_code, 200)
        titles = [row['title'] for row in response.json()]
        self.assertIn('Meaningful Structures', titles)

    def test_note_list_scope_all_includes_public_notes_from_other_users(self):
        # Foreign creator publishes one public note and one private note.
        foreign_user = User.objects.create_user(username='stranger@example.com', password='pw')
        foreign_creator = Creator.objects.create(user_id=foreign_user)
        foreign_course = Course.objects.create(
            creator_id=foreign_creator,
            slug='foreign-catalog',
            title='Foreign Catalog',
        )
        Note.objects.create(
            creator_id=foreign_creator,
            course_id=foreign_course,
            sharing_id='foreign-pub',
            title='Foreign Public Note',
            is_public=True,
            content='Shared reading for everyone.',
        )
        Note.objects.create(
            creator_id=foreign_creator,
            course_id=foreign_course,
            sharing_id='foreign-priv',
            title='Foreign Private Note',
            is_public=False,
            content='Private draft.',
        )
        # Own note (private) to confirm personal scope still works.
        Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='own-priv',
            title='Own Private Note',
        )

        personal_response = self.client.get(
            '/api/v1/notes/?scope=personal',
            **self._auth_headers(),
        )
        self.assertEqual(personal_response.status_code, 200)
        personal_titles = [row['title'] for row in personal_response.json()]
        self.assertIn('Own Private Note', personal_titles)
        self.assertNotIn('Foreign Public Note', personal_titles)
        self.assertNotIn('Foreign Private Note', personal_titles)

        all_response = self.client.get(
            '/api/v1/notes/?scope=all',
            **self._auth_headers(),
        )
        self.assertEqual(all_response.status_code, 200)
        all_titles = [row['title'] for row in all_response.json()]
        self.assertIn('Own Private Note', all_titles)
        self.assertIn('Foreign Public Note', all_titles)
        # Foreign-owned private notes must never leak into scope=all.
        self.assertNotIn('Foreign Private Note', all_titles)

    def test_course_subscribe_open_and_ordering_are_synced(self):
        course_a = Course.objects.create(
            creator_id=self.creator,
            slug='course-a',
            title='Course A',
        )
        course_b = Course.objects.create(
            creator_id=self.creator,
            slug='course-b',
            title='Course B',
        )

        subscribe_a = self.client.post(
            f'/api/v1/courses/{course_a.id}/subscribe/',
            data=json.dumps({}),
            content_type='application/json',
            **self._auth_headers(),
        )
        subscribe_b = self.client.post(
            f'/api/v1/courses/{course_b.id}/subscribe/',
            data=json.dumps({}),
            content_type='application/json',
            **self._auth_headers(),
        )
        self.assertEqual(subscribe_a.status_code, 200)
        self.assertEqual(subscribe_b.status_code, 200)

        open_response = self.client.post(
            f'/api/v1/courses/{course_a.id}/open/',
            data=json.dumps({}),
            content_type='application/json',
            **self._auth_headers(),
        )
        self.assertEqual(open_response.status_code, 200)

        ordering_response = self.client.get('/api/v1/courses/', **self._auth_headers())
        self.assertEqual(ordering_response.status_code, 200)
        ordered_ids = [row['id'] for row in ordering_response.json()[:2]]
        self.assertEqual(ordered_ids[0], course_a.id)
        self.assertIn(course_b.id, ordered_ids)
        self.assertTrue(
            CourseSubscription.objects.filter(
                creator_id=self.creator,
                course_id=course_a,
                is_active=True,
            ).exists()
        )
        self.assertEqual(
            CourseOperationLog.objects.filter(
                creator_id=self.creator,
                course_id=course_a,
                operation_type=CourseOperationTypeChoices.OPEN,
            ).count(),
            1,
        )

    def test_course_create_is_idempotent_for_client_course_id(self):
        payload = {
            'title': 'Offline-created course',
            'description': 'Created locally and synced later.',
            'client_course_id': 'course-local-abc',
        }

        first_response = self.client.post(
            '/api/v1/courses/',
            data=json.dumps(payload),
            content_type='application/json',
            **self._auth_headers(),
        )
        second_response = self.client.post(
            '/api/v1/courses/',
            data=json.dumps(payload),
            content_type='application/json',
            **self._auth_headers(),
        )

        self.assertEqual(first_response.status_code, 201)
        self.assertEqual(second_response.status_code, 200)
        self.assertEqual(first_response.json()['id'], second_response.json()['id'])
        self.assertEqual(
            Course.objects.filter(
                creator_id=self.creator,
                client_course_id='course-local-abc',
            ).count(),
            1,
        )

    def test_course_reorder_rewrites_sort_order_for_owned_courses(self):
        course_a = Course.objects.create(
            creator_id=self.creator,
            slug='reorder-a',
            title='Reorder Alpha',
        )
        course_b = Course.objects.create(
            creator_id=self.creator,
            slug='reorder-b',
            title='Reorder Bravo',
        )
        course_c = Course.objects.create(
            creator_id=self.creator,
            slug='reorder-c',
            title='Reorder Charlie',
        )

        response = self.client.post(
            '/api/v1/courses/reorder/',
            data=json.dumps({'course_ids': [course_c.id, course_a.id, course_b.id]}),
            content_type='application/json',
            **self._auth_headers(),
        )

        self.assertEqual(response.status_code, 200)
        course_a.refresh_from_db()
        course_b.refresh_from_db()
        course_c.refresh_from_db()
        self.assertEqual(course_c.sort_order, 1)
        self.assertEqual(course_a.sort_order, 2)
        self.assertEqual(course_b.sort_order, 3)

        payload = response.json()
        returned_ids = [row['id'] for row in payload]
        # The user-ordered trio should appear in the requested sequence right
        # after any pinned default (Inbox) category.
        self.assertIn(course_c.id, returned_ids)
        self.assertIn(course_a.id, returned_ids)
        self.assertIn(course_b.id, returned_ids)
        non_default = [row for row in payload if not row.get('is_default')]
        ordered_custom = [row['id'] for row in non_default if row['id'] in {course_a.id, course_b.id, course_c.id}]
        self.assertEqual(ordered_custom, [course_c.id, course_a.id, course_b.id])

    def test_course_reorder_rejects_non_list_payload(self):
        response = self.client.post(
            '/api/v1/courses/reorder/',
            data=json.dumps({'course_ids': 'not-a-list'}),
            content_type='application/json',
            **self._auth_headers(),
        )
        self.assertEqual(response.status_code, 400)

    def test_course_reorder_ignores_courses_owned_by_other_users(self):
        other_user = User.objects.create_user(username='intruder@example.com', password='pw')
        other_creator = Creator.objects.create(user_id=other_user)
        foreign_course = Course.objects.create(
            creator_id=other_creator,
            slug='foreign-course',
            title='Foreign Course',
        )
        own_course = Course.objects.create(
            creator_id=self.creator,
            slug='own-course',
            title='Own Course',
        )

        response = self.client.post(
            '/api/v1/courses/reorder/',
            data=json.dumps({'course_ids': [foreign_course.id, own_course.id]}),
            content_type='application/json',
            **self._auth_headers(),
        )

        self.assertEqual(response.status_code, 200)
        foreign_course.refresh_from_db()
        own_course.refresh_from_db()
        # The foreign course must not have been touched.
        self.assertEqual(foreign_course.sort_order, 0)
        # Our own course should be the first custom-ordered entry (index 1).
        self.assertEqual(own_course.sort_order, 1)

    def test_planner_completion_removes_event_from_active_week_payloads(self):
        event = PlannerEvent.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            title='Finish module',
            event_date=timezone.localdate() + timedelta(days=1),
            difficulty_weight=4,
        )

        patch_response = self.client.patch(
            f'/api/v1/planner-events/{event.id}/',
            data=json.dumps({'is_completed': True}),
            content_type='application/json',
            **self._auth_headers(),
        )
        self.assertEqual(patch_response.status_code, 200)
        event.refresh_from_db()
        self.assertTrue(event.is_completed)
        self.assertIsNotNone(event.completed_at)

        planner_response = self.client.get(
            '/api/v1/planner-events/',
            **self._auth_headers(),
        )
        self.assertEqual(planner_response.status_code, 200)
        self.assertEqual(planner_response.json(), [])

        week_response = self.client.get(
            f'/api/v1/activity/week/?start_date={timezone.localdate().isoformat()}',
            **self._auth_headers(),
        )
        self.assertEqual(week_response.status_code, 200)
        self.assertEqual(week_response.json()['deadlines'], [])

    def test_admin_can_restore_template_courses_into_partial_catalog(self):
        Course.objects.filter(id=self.course.id).delete()
        Note.objects.filter(creator_id=self.creator).delete()
        existing = Course.objects.create(
            creator_id=self.creator,
            slug='vibe-coding-101',
            title='Vibe Coding 101',
        )
        admin = User.objects.create_user(
            username='admin-restorer',
            email='admin-restorer@example.com',
            password='pw',
            is_active=True,
            is_staff=True,
            is_superuser=True,
        )
        admin_token = Token.objects.create(user=admin)

        response = self.client.post(
            '/api/v1/admin/template-courses/restore/',
            data=json.dumps({}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Token {admin_token.key}',
        )

        self.assertEqual(response.status_code, 200)
        slugs = list(Course.objects.order_by('slug').values_list('slug', flat=True))
        self.assertIn(existing.slug, slugs)
        self.assertIn('meaning-of-work-in-age-of-ai', slugs)
        self.assertIn('self-identity-and-expression-in-modern-arts', slugs)
        # Template courses must never be marked as default — only the user's
        # Inbox should carry is_default=True.
        template_defaults = Course.objects.filter(
            slug__in=['vibe-coding-101', 'meaning-of-work-in-age-of-ai',
                       'self-identity-and-expression-in-modern-arts'],
            is_default=True,
        )
        self.assertEqual(template_defaults.count(), 0,
                         'Template courses must not be marked as default')


class CourseDeleteApiTests(TestCase):
    """Verify DELETE /api/v1/courses/<id>/ moves notes and removes course."""

    def setUp(self):
        self.client = Client()
        self.user = User.objects.create_user(username='deleter', password='pw')
        self.creator = Creator.objects.create(user_id=self.user)
        self.token = Token.objects.create(user=self.user)
        # Default category (Inbox)
        self.inbox = Course.objects.create(
            creator_id=self.creator, slug='inbox-del', title='Inbox',
            is_default=True,
        )
        # Non-default category to delete
        self.target = Course.objects.create(
            creator_id=self.creator, slug='to-delete', title='To Delete',
        )
        # Notes inside the target category
        self.note1 = Note.objects.create(
            creator_id=self.creator, course_id=self.target,
            sharing_id='del-n1', title='Note in target',
        )
        self.note2 = Note.objects.create(
            creator_id=self.creator, course_id=self.target,
            sharing_id='del-n2', title='Another note',
        )

    def _auth(self):
        return {'HTTP_AUTHORIZATION': f'Token {self.token.key}'}

    def test_delete_moves_notes_to_inbox(self):
        resp = self.client.delete(
            f'/api/v1/courses/{self.target.id}/', **self._auth(),
        )
        self.assertEqual(resp.status_code, 204)
        # Course is gone
        self.assertFalse(Course.objects.filter(pk=self.target.id).exists())
        # Notes moved to Inbox
        self.note1.refresh_from_db()
        self.note2.refresh_from_db()
        self.assertEqual(self.note1.course_id_id, self.inbox.id)
        self.assertEqual(self.note2.course_id_id, self.inbox.id)

    def test_delete_default_category_rejected(self):
        resp = self.client.delete(
            f'/api/v1/courses/{self.inbox.id}/', **self._auth(),
        )
        self.assertEqual(resp.status_code, 400)
        self.assertTrue(Course.objects.filter(pk=self.inbox.id).exists())

    def test_delete_other_users_category_rejected(self):
        other_user = User.objects.create_user(username='other', password='pw')
        other_creator = Creator.objects.create(user_id=other_user)
        other_course = Course.objects.create(
            creator_id=other_creator, slug='other-c', title='Other',
        )
        resp = self.client.delete(
            f'/api/v1/courses/{other_course.id}/', **self._auth(),
        )
        self.assertEqual(resp.status_code, 403)
        self.assertTrue(Course.objects.filter(pk=other_course.id).exists())

    def test_delete_unauthenticated_rejected(self):
        resp = self.client.delete(f'/api/v1/courses/{self.target.id}/')
        self.assertEqual(resp.status_code, 401)
        self.assertTrue(Course.objects.filter(pk=self.target.id).exists())


class NoteUuidApiTests(TestCase):
    """Tests for UUID-based note access and comment notes."""

    def setUp(self):
        self.client = Client()
        self.user = User.objects.create_user(username='uuidowner', password='pw')
        self.creator = Creator.objects.create(user_id=self.user)
        self.token = Token.objects.create(user=self.user)
        self.course = Course.objects.create(
            creator_id=self.creator, slug='uuid-course', title='UUID Course',
        )
        self.public_note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='uuid-pub',
            title='Public UUID Note',
            content='# Public\n\nVisible to all.',
            is_public=True,
        )
        self.private_note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='uuid-priv',
            title='Private UUID Note',
            content='# Private\n\nOwner only.',
            is_public=False,
        )

    def _auth(self):
        return {'HTTP_AUTHORIZATION': f'Token {self.token.key}'}

    def test_get_public_note_by_uuid_anonymous(self):
        response = self.client.get(
            f'/api/v1/notes/uuid/{self.public_note.uuid}/',
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['title'], 'Public UUID Note')
        self.assertFalse(data['can_edit'])

    def test_get_public_note_by_uuid_owner(self):
        response = self.client.get(
            f'/api/v1/notes/uuid/{self.public_note.uuid}/',
            **self._auth(),
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()['can_edit'])

    def test_get_private_note_by_uuid_anonymous_rejected(self):
        response = self.client.get(
            f'/api/v1/notes/uuid/{self.private_note.uuid}/',
        )
        self.assertEqual(response.status_code, 400)

    def test_get_private_note_by_uuid_other_user_rejected(self):
        other = User.objects.create_user(username='stranger', password='pw')
        other_token = Token.objects.create(user=other)
        Creator.objects.create(user_id=other)
        response = self.client.get(
            f'/api/v1/notes/uuid/{self.private_note.uuid}/',
            HTTP_AUTHORIZATION=f'Token {other_token.key}',
        )
        self.assertEqual(response.status_code, 400)

    def test_patch_note_by_uuid_owner(self):
        response = self.client.patch(
            f'/api/v1/notes/uuid/{self.public_note.uuid}/',
            data=json.dumps({'title': 'Renamed'}),
            content_type='application/json',
            **self._auth(),
        )
        self.assertEqual(response.status_code, 200)
        self.public_note.refresh_from_db()
        self.assertEqual(self.public_note.title, 'Renamed')

    def test_patch_note_by_uuid_non_owner_rejected(self):
        other = User.objects.create_user(username='intruder', password='pw')
        other_token = Token.objects.create(user=other)
        Creator.objects.create(user_id=other)
        response = self.client.patch(
            f'/api/v1/notes/uuid/{self.public_note.uuid}/',
            data=json.dumps({'title': 'Hacked'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Token {other_token.key}',
        )
        self.assertEqual(response.status_code, 403)

    def test_delete_note_by_uuid_owner(self):
        response = self.client.delete(
            f'/api/v1/notes/uuid/{self.public_note.uuid}/',
            **self._auth(),
        )
        self.assertEqual(response.status_code, 204)
        self.public_note.refresh_from_db()
        self.assertIsNotNone(self.public_note.deleted_at)

    def test_note_uuid_in_summary_serializer(self):
        response = self.client.get('/api/v1/notes/', **self._auth())
        self.assertEqual(response.status_code, 200)
        for row in response.json():
            self.assertIn('uuid', row)
            self.assertIsNotNone(row['uuid'])

    def test_create_comment_note_with_source(self):
        response = self.client.post(
            '/api/v1/notes/',
            data=json.dumps({
                'title': 'My Comment',
                'content': 'Great article!',
                'note_type': 'C',
                'source_note_uuid': str(self.public_note.uuid),
            }),
            content_type='application/json',
            **self._auth(),
        )
        self.assertEqual(response.status_code, 201)
        data = response.json()
        self.assertEqual(data['note_type'], 'C')
        self.assertEqual(data['source_note_uuid'], str(self.public_note.uuid))

    def test_delete_source_note_makes_comments_private(self):
        comment = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='comment-1',
            title='Comment on public',
            content='This is a comment.',
            note_type='C',
            source_note=self.public_note,
            is_public=True,
        )
        self.client.delete(
            f'/api/v1/notes/{self.public_note.id}/',
            **self._auth(),
        )
        comment.refresh_from_db()
        self.assertFalse(comment.is_public)
        self.assertIsNone(comment.deleted_at)

    def test_nonexistent_uuid_returns_404(self):
        import uuid as _uuid
        response = self.client.get(
            f'/api/v1/notes/uuid/{_uuid.uuid4()}/',
        )
        self.assertEqual(response.status_code, 404)


class CalendarParsingTests(TestCase):
    def test_parse_ical_datetime_accepts_minute_precision(self):
        parsed = parse_ical_datetime('20260321T1500Z')

        self.assertEqual(parsed.tzinfo, dt_timezone.utc)
        self.assertEqual(parsed.year, 2026)
        self.assertEqual(parsed.hour, 15)
        self.assertEqual(parsed.minute, 0)


class NormalizeCalendarUrlTests(TestCase):
    def test_direct_ical_url_is_returned_as_is(self):
        url = (
            'https://calendar.google.com/calendar/ical/'
            'example%40group.calendar.google.com/public/basic.ics'
        )
        self.assertEqual(normalize_calendar_url(url), url)

    def test_icloud_webcal_passthrough(self):
        url = 'https://p123-caldav.icloud.com/published/2/abcd'
        self.assertEqual(normalize_calendar_url(url), url)

    def test_google_embed_src_rewrite(self):
        url = (
            'https://calendar.google.com/calendar/embed?'
            'src=example%40group.calendar.google.com&ctz=Asia%2FShanghai'
        )
        self.assertEqual(
            normalize_calendar_url(url),
            'https://calendar.google.com/calendar/ical/'
            'example%40group.calendar.google.com/public/basic.ics',
        )

    def test_google_cid_rewrite(self):
        # base64-url of "example@group.calendar.google.com"
        import base64
        cid = base64.urlsafe_b64encode(
            b'example@group.calendar.google.com'
        ).decode('ascii').rstrip('=')
        url = f'https://calendar.google.com/calendar/u/0/r?cid={cid}'
        self.assertEqual(
            normalize_calendar_url(url),
            'https://calendar.google.com/calendar/ical/'
            'example%40group.calendar.google.com/public/basic.ics',
        )

    def test_empty_url_returned_unchanged(self):
        self.assertEqual(normalize_calendar_url(''), '')


class WelcomeNoteSeedingTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='welcome-user', password='pw')
        self.creator = Creator.objects.create(user_id=self.user)

    def test_seed_creates_inbox_and_welcome_note(self):
        # Brand-new creator, no Inbox yet.
        self.assertFalse(
            Course.objects.filter(creator_id=self.creator).exists()
        )
        note = seed_inbox_and_welcome_note(self.creator)

        self.assertIsNotNone(note)
        inbox = Course.objects.get(creator_id=self.creator, is_default=True)
        self.assertEqual(inbox.title, 'Inbox')
        self.assertEqual(note.course_id, inbox)
        self.assertIn('Welcome to Notechondria', note.title)
        self.assertEqual(
            NoteBlock.objects.filter(note_id=note).count(), 2
        )

    def test_seed_is_idempotent_when_inbox_has_notes(self):
        inbox = Course.objects.create(
            creator_id=self.creator,
            slug='inbox-existing',
            title='Inbox',
            is_default=True,
        )
        Note.objects.create(
            creator_id=self.creator,
            course_id=inbox,
            sharing_id='existing-note',
            title='Existing',
        )

        result = seed_inbox_and_welcome_note(self.creator)

        self.assertIsNone(result)
        self.assertEqual(
            Note.objects.filter(creator_id=self.creator, course_id=inbox).count(),
            1,
        )

    def test_seed_reuses_existing_empty_inbox(self):
        inbox = Course.objects.create(
            creator_id=self.creator,
            slug='inbox-empty',
            title='Inbox',
            is_default=True,
        )

        note = seed_inbox_and_welcome_note(self.creator)

        self.assertIsNotNone(note)
        self.assertEqual(note.course_id_id, inbox.id)
        self.assertEqual(
            Course.objects.filter(creator_id=self.creator, is_default=True).count(),
            1,
        )
