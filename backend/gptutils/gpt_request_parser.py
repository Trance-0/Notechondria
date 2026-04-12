"""Stub module for AI chat request parsing.

The original implementation called the OpenAI Python SDK (`openai`) directly
and used `tiktoken` for local token counting. Both were removed from the
backend's requirements to cut deploy time and container size — future AI
integration will go through a separate service reached via plain HTTP
(e.g. `requests.post(...)`), not an SDK bundled into this Django process.

The existing `Conversation` / `Message` models, views, forms, templates,
migrations, and URL routes are left intact so the scaffolding is ready to
wire into a new HTTP-based client. Any function below that previously
performed AI work now raises `NotImplementedError` with a pointer at the
deferred rewrite.
"""

import logging

logger = logging.getLogger("django")

_AI_DISABLED_MESSAGE = (
    "AI chat generation is disabled in this build. The openai SDK and "
    "tiktoken were removed; reimplement this call against the future AI "
    "microservice via HTTP (requests.post to its chat endpoint) before "
    "re-enabling chat creation in the UI."
)


def get_openai_client():
    raise NotImplementedError(_AI_DISABLED_MESSAGE)


def generate_message(conversation):
    raise NotImplementedError(_AI_DISABLED_MESSAGE)


def generate_stream_message(conversation):
    raise NotImplementedError(_AI_DISABLED_MESSAGE)


def add_token(message):
    logger.debug(
        "add_token skipped for message %s — token accounting deferred to the "
        "future AI microservice.",
        getattr(message, "id", "<unsaved>"),
    )
