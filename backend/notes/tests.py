import json
from datetime import timedelta

from django.contrib.auth.models import User
from django.utils import timezone
from django.test import Client, RequestFactory, TestCase
from django.contrib.messages.storage.fallback import FallbackStorage
from rest_framework.authtoken.models import Token

from creators.models import Creator
from notechondria.utils import check_is_creator, generate_unique_id, get_object_or_None
from .models import Course, HeatmapActivity, Note, NoteBlock, NoteBlockTypeChoices, PlannerEvent


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
        future_cell = next(
            cell for cell in payload['cells']
            if cell['date'] == (timezone.localdate() + timedelta(days=2)).isoformat()
        )
        self.assertEqual(future_cell['future_value'], 3)

    def test_planner_event_create_endpoint(self):
        response = self.client.post(
            '/api/v1/planner-events/',
            data=json.dumps({
                'title': 'Review sprint',
                'event_date': (timezone.localdate() + timedelta(days=1)).isoformat(),
                'difficulty_weight': 2,
                'course_id': self.course.id,
            }),
            content_type='application/json',
            **self._auth_headers(),
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(PlannerEvent.objects.count(), 1)
