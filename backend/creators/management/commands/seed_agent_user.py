"""Create (or refresh) the local agent-testing identity.

Gives a coding agent a non-interactive way to obtain a verified user
plus a fresh ``ntc_`` API key, so authenticated REST + MCP flows can be
exercised against a local stack without the owner clicking through the
web UI (see ``docs/testing/agent_remote_testing.md``).

Behaviour:

* **Guarded.** Refuses to run unless ``settings.DEBUG`` is true or the
  ``ALLOW_AGENT_SEED=1`` env var is set, so it can never mint a
  credential on a production deployment by accident.
* **Idempotent.** Re-running reuses the existing ``agent-tester`` user
  and simply rotates its API key (the plaintext is only ever printed,
  never stored — same contract as ``/api/v1/auth/rotate-api-key/``).
* **Greppable output.** The last line is
  ``NOTECHONDRIA_API_KEY=ntc_...`` so a script can ``eval`` or grep it.

Usage (Docker full stack)::

    docker compose exec app python manage.py seed_agent_user
"""

import hashlib
import os
import secrets

from django.conf import settings
from django.contrib.auth.models import User
from django.core.management.base import BaseCommand, CommandError

from creators.utils import ensure_creator

AGENT_USERNAME = "agent-tester"
AGENT_EMAIL = "agent-tester@localhost.invalid"


class Command(BaseCommand):
    help = (
        "Create or refresh the local 'agent-tester' user and print a fresh "
        "ntc_ API key. Guarded: requires DEBUG=True or ALLOW_AGENT_SEED=1."
    )

    def handle(self, *args, **options):
        allowed = settings.DEBUG or os.environ.get("ALLOW_AGENT_SEED") == "1"
        if not allowed:
            raise CommandError(
                "Agent test identity was not created: "
                "Backend.Creators.Auth/seed_agent_user — refusing outside "
                "DEBUG; set ALLOW_AGENT_SEED=1 to run on this deployment."
            )

        user, created = User.objects.get_or_create(
            username=AGENT_USERNAME,
            defaults={"email": AGENT_EMAIL, "is_active": True},
        )
        if created:
            # The API key is the credential; no password login path.
            user.set_unusable_password()
            user.save(update_fields=["password"])
        elif not user.is_active:
            user.is_active = True
            user.save(update_fields=["is_active"])

        creator = ensure_creator(user)

        plaintext = f"ntc_{secrets.token_hex(16)}"
        creator.api_key_hash = hashlib.sha256(plaintext.encode()).hexdigest()
        creator.api_key_prefix = plaintext[:8]
        creator.save(update_fields=["api_key_hash", "api_key_prefix"])

        self.stdout.write(
            f"agent user {'created' if created else 'reused'}: "
            f"username={AGENT_USERNAME} user_id={user.id} creator_id={creator.id}"
        )
        self.stdout.write("api key rotated; previous key (if any) is now invalid")
        self.stdout.write(f"NOTECHONDRIA_API_KEY={plaintext}")
