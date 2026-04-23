# GitHub App Integration Guide

This project supports a GitHub App integration path for repo import/sync workflows.

## 1) Create GitHub App

In GitHub Developer Settings:

- App name: `Notechondria Sync`
- Homepage URL: your frontend URL
- Callback URL: `https://<backend-host>/integrations/github/callback`
- Webhook URL: `https://<backend-host>/integrations/github/webhook`
- Webhook secret: generate random 32+ chars

### Permissions
Set minimum permissions:
- Repository contents: **Read & write**
- Pull requests: **Read & write**
- Metadata: **Read-only**

### Events
Subscribe to:
- `push`
- `pull_request`
- `installation`
- `installation_repositories`

## 2) Install app on repository/org

Install the app on target repositories used for course templates.

## 3) Configure server env

Add these variables to `.env`:

- `GITHUB_APP_ID`
- `GITHUB_APP_CLIENT_ID`
- `GITHUB_APP_CLIENT_SECRET`
- `GITHUB_APP_PRIVATE_KEY_PATH`
- `GITHUB_APP_WEBHOOK_SECRET`

## 4) Verify webhook flow

1. Trigger a push event.
2. Confirm backend receives and verifies `X-Hub-Signature-256`.
3. Confirm event is logged and queued for sync.

## 5) Recommended backend implementation steps

1. Add `/integrations/github/callback` endpoint to exchange OAuth code.
2. Store installation IDs per user/org.
3. Create adapter methods for:
   - Read template files from repository contents API.
   - Open PR for course edits.
4. Add idempotent webhook consumer with retry on transient failures.

## 6) Security checklist

- Never commit private key content to git.
- Validate webhook signatures on every request.
- Restrict scopes to least privilege.
- Encrypt stored tokens at rest.
