"""Push every existing Notechondria ``User`` (and its ``Creator``
profile + any linked ``SocialAccount`` rows) into the configured
Casdoor instance, then stamp ``Creator.casdoor_sub`` so the next
JWT-validated request through
``creators.casdoor_auth.CasdoorJWTAuthentication`` takes the fast
``Creator.casdoor_sub == claims['id']`` path.

This is the one-time cutover step from
``docs/integrations/casdoor-migration.md``: phase 4 (cutover) is now
unblocked because phase 1-3 (auth class, Flutter SDK leg, bind/unlink
endpoints) all shipped between 0.1.96 and 0.1.99. Running this
command is what flips a deployment from "Casdoor optional" to
"Casdoor only" for the existing user base.

Behaviour:

* **Idempotent.** Skips users whose ``Creator.casdoor_sub`` is
  already populated. Safe to re-run after a partial / aborted batch;
  the `--retry-existing` flag forces a re-push for users that already
  have a Casdoor row but have somehow drifted from the local profile
  (e.g. the operator changed their display name in Casdoor and wants
  the local copy to win).
* **Per-user fault tolerance.** A failure on one user (Casdoor 409,
  network blip, malformed email) logs an error and moves on. The
  batch returns a non-zero exit code only if at least one user
  failed *and* `--strict` was passed.
* **Heartbeat.** Prints a per-user line so the operator can see
  forward motion on a multi-thousand-user run; AGENTS.md §1.4 says
  any process that may run longer than 1 minute must show progress
  more often than once every 5 minutes.
* **Provider linkage.** When a user has a ``SocialAccount`` for
  Google or GitHub, that ``provider_uid`` is written to the matching
  field on the Casdoor user (``user.google``, ``user.github``) so
  Casdoor's own provider flow recognises the existing identity on
  the next sign-in. Users land on the same account without an
  explicit "link this provider" step.
* **Password handling.** Local Django password hashes can't be
  imported one-for-one (Casdoor uses different hashing schemes per
  application); the command sets a long random password on each
  Casdoor user and tells the operator to instruct users to use the
  "Forgot password?" link on the Casdoor login page once. Existing
  legacy logins through Notechondria's email/password fallback keep
  working until the operator removes the legacy view, so this is a
  gradual handoff.

Usage:

    python manage.py migrate_users_to_casdoor --dry-run
    python manage.py migrate_users_to_casdoor
    python manage.py migrate_users_to_casdoor --retry-existing --strict

Requires:

* ``CASDOOR_ENDPOINT``, ``CASDOOR_CLIENT_ID``,
  ``CASDOOR_CLIENT_SECRET``, ``CASDOOR_ORG_NAME``,
  ``CASDOOR_APP_NAME``, ``CASDOOR_CERTIFICATE`` populated in the
  environment (the same values backed by
  ``backend/creators/casdoor_auth.py``).
* The ``casdoor`` Python SDK (already in
  ``backend/requirements.txt`` since 0.1.96).
"""

from __future__ import annotations

import logging
import os
import secrets
import string
import time

from django.conf import settings
from django.contrib.auth.models import User
from django.core.management.base import BaseCommand, CommandError

from creators.models import Creator
from creators.casdoor_auth import _normalize_pem


logger = logging.getLogger("django")


# Length of the random password assigned to each migrated Casdoor
# user. Casdoor hashes it server-side; the operator never sees the
# plaintext, and the Casdoor "forgot password" flow lets users pick
# their own afterwards.
_RANDOM_PASSWORD_LEN = 40


def _random_password() -> str:
    alphabet = string.ascii_letters + string.digits + "-_"
    return "".join(secrets.choice(alphabet) for _ in range(_RANDOM_PASSWORD_LEN))


class Command(BaseCommand):
    help = (
        "Push every Notechondria User into Casdoor and backfill "
        "Creator.casdoor_sub so subsequent JWT logins take the fast "
        "path. Idempotent. Use --dry-run to preview."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help=(
                "Walk the user table and print what would be written, "
                "but do not call the Casdoor API."
            ),
        )
        parser.add_argument(
            "--retry-existing",
            action="store_true",
            help=(
                "Also re-push users whose Creator.casdoor_sub is "
                "already populated. Useful for fixing drift after a "
                "manual edit in the Casdoor admin UI."
            ),
        )
        parser.add_argument(
            "--strict",
            action="store_true",
            help=(
                "Exit non-zero if any single user fails to migrate. "
                "Default is to log + continue."
            ),
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=0,
            help=(
                "Stop after this many candidate users (0 = no limit). "
                "Useful for smoke-testing the wiring against a "
                "production DB before doing the full batch."
            ),
        )
        parser.add_argument(
            "--admin-password-from-env",
            action="store_true",
            help=(
                "When the user being upserted matches "
                "DJANGO_SUPERUSER_USERNAME, set their Casdoor password "
                "to the value of DJANGO_SUPERUSER_PASSWORD instead of "
                "a random string. Lets the operator keep the admin's "
                "password in lockstep with the .env file across the "
                "migration. Other users still get a random password."
            ),
        )

    # ------------------------------------------------------------------
    # entry point
    # ------------------------------------------------------------------
    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        retry_existing = options["retry_existing"]
        strict = options["strict"]
        limit = options["limit"]
        use_admin_env_password = options["admin_password_from_env"]

        admin_username = (
            os.getenv("DJANGO_SUPERUSER_USERNAME") or "admin"
        ).strip()
        admin_password = os.getenv("DJANGO_SUPERUSER_PASSWORD") or ""
        if use_admin_env_password and not admin_password:
            raise CommandError(
                "Cannot migrate users: "
                "Backend.Creators.MigrateToCasdoor/handle — "
                "--admin-password-from-env requested but "
                "DJANGO_SUPERUSER_PASSWORD is unset / empty in this "
                "shell. Set it (or drop the flag and accept a random "
                "admin password)."
            )

        sdk = self._build_admin_sdk()

        qs = (
            User.objects.filter(is_active=True)
            .order_by("id")
            .select_related()
        )
        candidates = list(qs)
        total = len(candidates)
        self.stdout.write(
            f"Migrating {total} active user(s) to Casdoor "
            f"({settings.CASDOOR_ENDPOINT}, org={settings.CASDOOR_ORG_NAME!r}, "
            f"app={settings.CASDOOR_APP_NAME!r}). "
            f"dry_run={dry_run} retry_existing={retry_existing} strict={strict}."
        )

        succeeded = 0
        skipped = 0
        failed = 0
        started_at = time.time()

        for idx, user in enumerate(candidates, start=1):
            if limit and idx > limit:
                self.stdout.write(f"Reached --limit={limit}; stopping early.")
                break

            creator = Creator.objects.filter(user_id=user).first()
            if creator is None:
                # Users without a Creator profile (e.g. the bootstrap
                # admin before first login) are skipped — they have
                # no Notechondria-specific state worth migrating.
                skipped += 1
                self.stdout.write(
                    f"[{idx}/{total}] skip {user.username!r}: "
                    "no Creator profile attached."
                )
                continue

            if creator.casdoor_sub and not retry_existing:
                skipped += 1
                self.stdout.write(
                    f"[{idx}/{total}] skip {user.username!r}: "
                    f"already linked to Casdoor sub={creator.casdoor_sub[:12]!r}."
                )
                continue

            # Per-user password resolution. Admin row gets the .env
            # password if --admin-password-from-env was passed; everyone
            # else gets a random string + the Casdoor "Forgot password"
            # handoff. Match by username (case-insensitive) so the
            # operator doesn't have to keep DJANGO_SUPERUSER_USERNAME in
            # sync with their actual admin row capitalisation.
            if (
                use_admin_env_password
                and user.username.lower() == admin_username.lower()
            ):
                user_password = admin_password
            else:
                user_password = _random_password()

            try:
                sub = self._upsert_casdoor_user(
                    sdk=sdk,
                    user=user,
                    creator=creator,
                    dry_run=dry_run,
                    password=user_password,
                )
            except Exception as exc:  # noqa: BLE001
                failed += 1
                logger.warning(
                    "Casdoor migration failed for %s: "
                    "Backend.Creators.MigrateToCasdoor/upsert — %s.",
                    user.username,
                    exc,
                )
                self.stderr.write(
                    f"[{idx}/{total}] FAIL {user.username!r}: {exc}"
                )
                continue

            if not dry_run:
                creator.casdoor_sub = sub
                creator.save(update_fields=["casdoor_sub"])

            succeeded += 1
            elapsed = time.time() - started_at
            rate = succeeded / elapsed if elapsed > 0 else 0
            self.stdout.write(
                f"[{idx}/{total}] ok   {user.username!r} "
                f"sub={sub[:12]!r} ({rate:.1f}/s)"
            )

        self.stdout.write("")
        self.stdout.write(
            f"Done. ok={succeeded} skipped={skipped} failed={failed} "
            f"({time.time() - started_at:.1f}s)."
        )

        if failed and strict:
            raise CommandError(
                f"{failed} user(s) failed to migrate; --strict requested. "
                "Re-run after investigating the FAIL log lines above."
            )

    # ------------------------------------------------------------------
    # Casdoor SDK wiring
    # ------------------------------------------------------------------
    def _build_admin_sdk(self):
        """Boot a CasdoorSDK with the same env vars used by the JWT
        verifier. Fails loudly when any required field is missing —
        this command is destructive enough that we want a clear stop
        rather than a half-applied migration."""
        missing = [
            name
            for name, val in [
                ("CASDOOR_ENDPOINT", settings.CASDOOR_ENDPOINT),
                ("CASDOOR_CLIENT_ID", settings.CASDOOR_CLIENT_ID),
                ("CASDOOR_CLIENT_SECRET", settings.CASDOOR_CLIENT_SECRET),
                ("CASDOOR_ORG_NAME", settings.CASDOOR_ORG_NAME),
                ("CASDOOR_APP_NAME", settings.CASDOOR_APP_NAME),
                ("CASDOOR_CERTIFICATE", settings.CASDOOR_CERTIFICATE),
            ]
            if not val
        ]
        if missing:
            raise CommandError(
                "Cannot migrate users: "
                "Backend.Creators.MigrateToCasdoor/build_sdk — "
                f"required env vars are unset: {', '.join(missing)}."
            )

        try:
            from casdoor import CasdoorSDK
        except ImportError as exc:
            raise CommandError(
                "Cannot migrate users: "
                "Backend.Creators.MigrateToCasdoor/build_sdk — "
                "the casdoor Python SDK is not installed. Run "
                "`pip install -r backend/requirements.txt` and retry."
            ) from exc

        return CasdoorSDK(
            endpoint=settings.CASDOOR_ENDPOINT,
            client_id=settings.CASDOOR_CLIENT_ID,
            client_secret=settings.CASDOOR_CLIENT_SECRET,
            certificate=_normalize_pem(settings.CASDOOR_CERTIFICATE),
            org_name=settings.CASDOOR_ORG_NAME,
            application_name=settings.CASDOOR_APP_NAME,
        )

    # ------------------------------------------------------------------
    # per-user upsert
    # ------------------------------------------------------------------
    def _upsert_casdoor_user(
        self, *, sdk, user, creator, dry_run, password
    ):
        """Idempotently push *user* into Casdoor. Returns the resolved
        ``id`` (Casdoor sub) so the caller can stamp it on
        ``creator.casdoor_sub``.

        Resolution order on Casdoor:

        1. ``get_user_by_email(email)`` — if the email already exists,
           reuse it (this catches users who self-signed up directly on
           the Casdoor side before this migration ran).
        2. Otherwise ``add_user(...)`` a fresh row.

        ``password`` is the Casdoor password to set on the row when
        we hit the add-user branch (the update branch never touches
        password — Casdoor users that already exist keep whatever
        they had). The caller picks the value:
        ``DJANGO_SUPERUSER_PASSWORD`` for the admin row when
        ``--admin-password-from-env`` is on, random otherwise.
        """
        from casdoor.user import User as CasdoorUser

        email = (user.email or "").strip().lower()
        username = user.username.strip()

        if dry_run:
            password_origin = "env" if password and len(password) < 40 else "random"
            self.stdout.write(
                f"   would upsert username={username!r} email={email!r} "
                f"display_name={(creator.username or username)!r} "
                f"password={password_origin}"
            )
            # Use the Notechondria pk as the dry-run "sub" so the log
            # output is stable and easy to diff between runs.
            return f"dry-run-{user.pk}"

        existing = None
        if email:
            try:
                existing = sdk.get_user_by_email(email)
            except Exception:  # noqa: BLE001
                # The Casdoor SDK raises on 404. Treat any exception
                # here as "user not found" and fall through to add.
                existing = None

        # Casdoor returns ``None`` (or {}) when there's no match.
        existing_id = ""
        if existing and isinstance(existing, dict):
            existing_id = (existing.get("id") or "").strip()

        cu = CasdoorUser()
        cu.owner = settings.CASDOOR_ORG_NAME
        cu.name = username
        cu.displayName = (creator.username or username) or username
        cu.email = email
        cu.emailVerified = bool(email)
        cu.avatar = (
            creator.avatar.url
            if getattr(creator, "avatar", None) and getattr(creator.avatar, "url", "")
            else ""
        )
        cu.signupApplication = settings.CASDOOR_APP_NAME
        cu.firstName = (user.first_name or "")[:30]
        cu.lastName = (user.last_name or "")[:150]
        if user.is_superuser:
            cu.isAdmin = True

        # 0.1.119: SocialAccount-backed provider pre-population is
        # gone along with the model. The migration command now only
        # ports the legacy email + password hash; provider linkage
        # (google / github) is set up directly on the Casdoor side
        # via the Application's Providers tab. Re-running this
        # command on a database where SocialAccount has already been
        # dropped (post-migration 0033) is the supported path.

        if existing_id:
            # Update path — preserve the existing Casdoor sub. The
            # SDK's update_user expects the user to carry the same
            # ``owner``/``name`` as the row being updated.
            cu.id = existing_id
            sdk.update_user(cu)
            return existing_id

        # Add path — Casdoor hashes the password we send. Caller
        # supplies it: DJANGO_SUPERUSER_PASSWORD for the admin row
        # (when --admin-password-from-env), random for everyone else.
        # Random-password users go through the Casdoor "Forgot
        # password?" flow on first sign-in to pick their own.
        cu.password = password
        sdk.add_user(cu)

        # Re-read so we can return the assigned ``id`` (Casdoor stamps
        # it server-side; the SDK's add_user returns the response
        # body, but its shape varies by version, so a follow-up read
        # is the durable way to get the sub).
        if email:
            try:
                added = sdk.get_user_by_email(email)
            except Exception:  # noqa: BLE001
                added = None
        else:
            added = None
        if added and isinstance(added, dict):
            sub = (added.get("id") or "").strip()
            if sub:
                return sub

        # Fallback: if we can't read the sub back, use the username
        # as the sub (Casdoor accepts username as a JWT id claim too).
        # The next sign-in will correct the stamp via
        # _resolve_user's email-fallback path.
        return username
