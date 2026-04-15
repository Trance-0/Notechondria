# AI integration — current state and forward plan

This file describes where AI-related code lives in Notechondria after the
0.1.18-series prune, and how future AI features should be wired in.

## TL;DR

- **No AI model ever runs inside the Django process.** `torch`,
  `torchaudio`, `torchvision`, `tiktoken`, `openai` (the SDK), and the
  transitive `numpy` / `sympy` / `networkx` / `mpmath` / `fsspec` packages
  were removed from [backend/requirements.txt](../../backend/requirements.txt)
  to cut deploy time and container size.
- **`backend/gptutils/` is a parked Django app.** The
  `Conversation`/`Message` models, views, forms, templates, migrations, and
  URL routes are all still registered — only the AI call sites in
  [backend/gptutils/gpt_request_parser.py](../../backend/gptutils/gpt_request_parser.py)
  have been stubbed out. Those stubs raise `NotImplementedError` with a
  pointer back here.
- **Future AI features call an external service over HTTP** (plain
  `requests.post(...)` or an async httpx call). No vendor SDK is re-added to
  the backend.

## Why this shape

The backend ran into three separate deploy-time failures that all traced
back to bundling AI libraries into the Django process:

1. Render free tier: the `torch` wheel alone is ~800 MB, which put cold
   boots well past the platform's memory/disk budget.
2. Northflank and Jenkins Docker builds: same problem, rebuilds were
   10+ minutes on every dependency change.
3. `tiktoken` and the OpenAI SDK pulled in a transitive dep tree that
   broke unrelated tests whenever `OPENAI_API_KEY` was missing from the
   environment at import time.

Per `AGENTS.md/AGENTS.md` §4.1 — "OpenAI / vendor SDK clients: initialize
**lazily at call time**, never at module import" — we went one step
further: the SDK is simply not installed. The few places that used to
call it raise `NotImplementedError` instead.

## Current layout

```text
backend/
├── gptutils/                       ← parked app; tables still in DB
│   ├── apps.py                     (verbose_name signals stub status)
│   ├── models.py                   (Conversation, Message — unchanged)
│   ├── views.py                    (still mounted at /gptutils/…)
│   ├── gpt_request_parser.py       (stub; raises NotImplementedError)
│   ├── urls.py / forms.py / admin.py / templates/
│   └── migrations/                 (0001 … 0015)
├── requirements.txt                (no AI packages)
├── requirements-render.txt         (same minimal set)
docs/
├── development/
│   └── ai_integration.md           (this file)
```

The stubbed functions in `gpt_request_parser.py` keep the original
signatures so callers in `views.py` still import and call them — the
raised exception surfaces in the UI as a 500, which is by design until
the replacement service exists.

## How to wire in a replacement AI service

When the external AI microservice is ready, do this — **do not** add the
OpenAI SDK back to requirements:

1. Add one env var pair per upstream: e.g. `AI_CHAT_URL` (the HTTPS
   endpoint) and `AI_CHAT_API_KEY` (the bearer). Document them in
   [sample.env](../../sample.env) and any deploy-target sample env.
2. In `gpt_request_parser.py`, replace the stub body of `generate_message`
   with a `requests.post(os.getenv("AI_CHAT_URL"), json=payload,
   headers={"Authorization": f"Bearer {os.getenv('AI_CHAT_API_KEY')}"},
   timeout=30)`. Keep `get_openai_client()` stubbed — it's only kept so
   pre-refactor imports resolve.
3. For streaming, return a generator that yields chunks from the
   upstream SSE/NDJSON response; the existing `generate_stream_message`
   signature already matches what the view expects.
4. Token counting: the upstream service is responsible for returning
   prompt/completion token counts in its response payload. Write them to
   `Conversation.total_prompt_tokens` and `total_completion_tokens`
   directly from the response body; do not reintroduce `tiktoken`.

## What was intentionally *not* moved

- **`course_template/` at repo root** — this is a curriculum template
  (README, modules, assignments, course.yaml) and is AI-adjacent but
  not AI-specific. It's referenced from `docs/index.md` and a validator
  script, so moving it would require chasing refs for no real benefit.
- **`sample/` fixtures** — these are the platform's seed courses. Not AI
  code.
- **The `gptutils` Django app layout** — renaming the app would force a
  data migration to rename `gptutils_conversation` → `<newname>_conversation`
  etc., which is risky without a test DB snapshot. Verbose name in the
  admin flags it as parked; the real signal for agents is this doc plus
  the module docstring in `gpt_request_parser.py`.

## Related environment variables

Unused today but still documented in [sample.env](../../sample.env) and
platform-specific env samples, because the future replacement service
may reuse the same names:

- `OPENAI_API_KEY` — leave empty; no code reads it anymore.

Any new `AI_*` variables added for the replacement service should be
documented in this file alongside a short note on which endpoint they
reach.
