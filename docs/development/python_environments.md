# Python Environment Setup for Developers

This repo's backend lives in `backend/` and is currently verified most often with `uv`, but plain `conda` + `pip` also works well for local development.

## Recommended Python version

Use **Python 3.11.4** for local backend work.

That matches:
- `runtime.txt`
- `.python-version`
- `backend/runtime.txt`
- `backend/.python-version`

## Option A: Conda + pip

Create and activate a clean env:

```bash
conda create -n notechondria-dev python=3.11.4 -y
conda activate notechondria-dev
```

Install backend dependencies:

```bash
cd backend
pip install -r requirements.txt
```

If you specifically want a Render-like runtime install path instead of the fuller backend dependency set:

```bash
cd backend
pip install -r requirements-render.txt
```

## Option B: uv-managed virtualenv

```bash
cd backend
uv venv .venv
source .venv/bin/activate
uv pip install -r requirements.txt
```

## Running backend tests

```bash
cd backend
DJANGO_SETTINGS_MODULE=notechondria.settings_test python manage.py test
```

Notes:
- `settings_test` uses SQLite in-memory for test runs.
- `settings_test` must define a non-empty `SECRET_KEY`, otherwise request/session/message tests will fail before app logic is exercised.
- GPT/OpenAI code should not initialize API clients at import time; tests should only require `OPENAI_API_KEY` when GPT paths are actually executed.

## Dependency maintenance rules

Do **not** blindly overwrite `backend/requirements.txt` with `pip freeze` from an arbitrary machine.
That tends to bake in:
- platform-specific noise
- transient local packages
- stale dev-only packages
- mismatches with Render/runtime constraints

Prefer this workflow instead:

1. install deliberately
2. test deliberately
3. update `requirements.txt` intentionally

Useful inspection commands:

```bash
pip list
pip freeze
conda list
conda env export --no-builds
```

If you want a local lock snapshot for debugging, write it to a temporary/local file rather than overwriting the tracked requirements file:

```bash
conda env export --no-builds > /tmp/notechondria-conda-env.yml
pip freeze > /tmp/notechondria-pip-freeze.txt
```

## Why the old `code_snippets/` env files were removed

The former snippet directory mixed together:
- redundant one-line shell snippets
- a stale Windows-specific `environment.yml`
- commands that wrote directly into tracked requirement files

That was more confusing than helpful.
This doc keeps the useful workflow, but without the dangerous or outdated bits.
