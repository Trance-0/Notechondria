import json
from datetime import datetime, time, timedelta, timezone as dt_timezone

from django.contrib.auth.models import User
from django.utils import timezone
from django.test import Client, RequestFactory, TestCase
from django.contrib.messages.storage.fallback import FallbackStorage
from rest_framework.authtoken.models import Token

from creators.models import Creator
from notechondria.utils import check_is_creator, generate_unique_id, get_object_or_None
from .models import CalendarFeed, Course, HeatmapActivity, Note, NoteActivitySession, NoteBlock, NoteBlockTypeChoices, NoteVersion, PlannerEvent
from .services import parse_ical_datetime


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

    def test_public_notes_are_visible_without_login_and_private_notes_are_hidden(self):
        public_note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='public-share',
            title='Public note',
            is_public=True,
            content='# Public note\n\nVisible.',
        )
        private_note = Note.objects.create(
            creator_id=self.creator,
            course_id=self.course,
            sharing_id='private-share',
            title='Private note',
            is_public=False,
            content='# Private note\n\nHidden.',
        )

        response = self.client.get('/api/v1/notes/')

        self.assertEqual(response.status_code, 200)
        titles = [row['title'] for row in response.json()]
        self.assertIn(public_note.title, titles)
        self.assertNotIn(private_note.title, titles)

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


class CalendarParsingTests(TestCase):
    def test_parse_ical_datetime_accepts_minute_precision(self):
        parsed = parse_ical_datetime('20260321T1500Z')

        self.assertEqual(parsed.tzinfo, dt_timezone.utc)
        self.assertEqual(parsed.year, 2026)
        self.assertEqual(parsed.hour, 15)
        self.assertEqual(parsed.minute, 0)
