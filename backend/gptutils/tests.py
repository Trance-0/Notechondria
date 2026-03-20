from django.contrib.auth.models import User
from django.test import TestCase

from creators.models import Creator
from .models import Conversation, GPTModelChoices, Message


class ConversationModelTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='chat-user', password='pw')
        self.creator = Creator.objects.create(user_id=self.user)

    def test_is_visual_model(self):
        visual = Conversation.objects.create(
            creator_id=self.creator,
            sharing_id='sharechat1',
            model=GPTModelChoices.GPT4V_1106,
        )
        plain = Conversation.objects.create(
            creator_id=self.creator,
            sharing_id='sharechat2',
            model=GPTModelChoices.PLAIN,
        )

        self.assertTrue(visual.is_visual_model())
        self.assertFalse(plain.is_visual_model())

    def test_get_system_prompt_dict(self):
        conversation = Conversation.objects.create(
            creator_id=self.creator,
            sharing_id='sharechat3',
            model=GPTModelChoices.GPT4_1106,
            system_prompt='Be concise',
        )

        payload = conversation.get_system_prompt_dict()
        self.assertEqual(payload['role'], 'system')
        self.assertEqual(payload['content'][0]['text'], 'Be concise')


class MessageModelTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='msg-user', password='pw')
        self.creator = Creator.objects.create(user_id=self.user)
        self.conversation = Conversation.objects.create(
            creator_id=self.creator,
            sharing_id='sharechat4',
            model=GPTModelChoices.PLAIN,
        )

    def test_body_and_extras_split_large_message(self):
        text = 'a' * 850
        message = Message.objects.create(conversation_id=self.conversation, text=text)

        self.assertEqual(len(message.body()), 800)
        self.assertEqual(len(message.extras()), 50)

    def test_body_for_short_message(self):
        message = Message.objects.create(conversation_id=self.conversation, text='short')

        self.assertEqual(message.body(), 'short')
        self.assertIsNone(message.extras())
