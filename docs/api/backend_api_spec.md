# Backend API Specification (MVP)

This document describes the current HTTP endpoints that can be consumed by the Flutter client and by integration tests.

## Authentication

The backend currently uses Django session authentication.

1. Login via `POST /creators/login`.
2. Reuse `sessionid` cookie for subsequent requests.

## Endpoints

### 1) Health/Home
- **GET** `/`
- **Description**: Returns homepage HTML.
- **Auth required**: No

### 2) List Notes (Learner Course List Proxy)
- **GET** `/notes/collections/`
- **Description**: Returns note collection page for current user.
- **Auth required**: Yes
- **Response**: HTML page with notes

### 3) Create Note
- **POST** `/notes/notes/new`
- **Description**: Creates a note and redirects to editor.
- **Auth required**: Yes
- **Form fields**:
  - `title` (string, required)
  - `description` (string, optional)

### 4) Edit Note
- **GET** `/notes/collections/edit/<note_id>`
- **Description**: Returns note editor page.
- **Auth required**: Yes

### 5) GPT Chat Main
- **GET** `/gptutils/`
- **Description**: Returns conversation landing page.
- **Auth required**: Yes

### 6) Create Chat
- **POST** `/gptutils/create_chat`
- **Description**: Creates a conversation.
- **Auth required**: Yes

## Example Requests

### Login then list notes
```bash
curl -i -c cookies.txt -X POST http://localhost:8000/creators/login \
  -d "username=demo" \
  -d "password=demo-password"

curl -i -b cookies.txt http://localhost:8000/notes/collections/
```

### Create note
```bash
curl -i -b cookies.txt -X POST http://localhost:8000/notes/notes/new \
  -d "title=Linear Algebra Sprint" \
  -d "description=Week 1 focuses on vectors"
```

## Planned JSON API (for Flutter production)

To reduce HTML coupling, add versioned JSON routes under `/api/v1/`:

- `GET /api/v1/courses/`
- `POST /api/v1/courses/`
- `GET /api/v1/courses/{id}/calendar`
- `GET /api/v1/activity`
- `PATCH /api/v1/users/me/settings`

These routes are documented targets for the next backend iteration.
