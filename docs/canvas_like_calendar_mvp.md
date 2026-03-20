# Canvas-like Calendar for Self-Study Tracking (MVP)

## One-liner
A calendar app with an infinite canvas where learners create courses, track deadlines, log evidence, and publish portfolios.

## Problem statement
Self-learners struggle to keep a single, visual place to plan and document progress. Traditional calendars show dates but hide the narrative; note apps capture reflections but lack timelines. This product combines both.

## Target users
- Self-learners (coding, languages, exams, reading plans)
- Career switchers building portfolio evidence
- Small study groups (optional in MVP)

## Core objects (data model)
### User
- id, handle, display_name
- privacy defaults (public profile? Y/N)
- timezone
- integrations (optional): github, google calendar, etc.

### Course
- id, owner_id
- title, description
- visibility: private | unlisted | public
- tags (e.g., "math", "rust", "history")
- status: active | archived
- forked_from_course_id (nullable)

### Task (a.k.a. milestone / assignment)
- id, course_id
- title, description
- due_date (nullable)
- state: todo | done
- completed_at (nullable)
- evidence: list of EvidenceItem
- reflections: list of ReflectionEntry

### EvidenceItem
- type: link | git_commit | git_pr | file | note
- url (nullable)
- provider (nullable): github, youtube, etc.
- text (nullable)
- created_at

### CanvasBoard
- id, course_id
- nodes: list of Node
- edges: list of Edge

Node
- id, type: task | note | link | section
- ref_id (nullable): points to Task or EvidenceItem
- position: x,y
- size: w,h
- content (for note/section)

Edge
- id, from_node_id, to_node_id
- label (optional)

## Primary views & flows
### A) Course creation
- Create course (title + optional template)
- Auto-create a default board + default calendar grouping

### B) Task creation
- Quick-add task from:
  - course page
  - calendar (click day → add)
  - canvas (create task card)
- Optional due date
- Optional effort estimate (minutes/hours) [MVP: store, don’t over-interpret]

### C) Completion logging
- One-click "Done"
- Optional modal: add reflection + evidence links

### D) Calendar view
- Month + week views
- Filters: course, status, visibility
- Drag task to reschedule

### E) Canvas view
- Infinite pan/zoom
- Create note nodes
- Drag tasks onto board (task cards)
- Link nodes (edges)
- Basic grouping/sections

### F) Sharing
- Course visibility:
  - Private: only owner
  - Unlisted: anyone with link
  - Public: appears on profile and discoverable
- Public board shows:
  - course summary
  - progress stats (tasks done / total)
  - selected artifacts (evidence links, reflections)
- No public commenting in MVP (moderation sinkhole)

### G) Profile (“repo-like”)
- List of courses with:
  - status (active/archived)
  - last activity date
  - progress bar
  - link to public board if public/unlisted

## Deadline horizon rule (3-month constraint)
- Allow tasks to exist without a due date indefinitely.
- For due dates: enforce a planning horizon.
  - due_date must be within 90 days of the date it is set/edited.
  - user can extend later, but only in increments within 90 days from “today”.

## MVP metrics
- Tasks completed per week
- Active courses count
- Evidence attachment rate

## Scope boundaries (explicit non-goals)
- AI syllabus parsing/import
- Full course collaboration with branching/merging
- Credential issuance / official transcripts
- Payment / marketplace
- Advanced analytics (time auditing, “credits” enforcement)

## Git-backed course template (baseline)
Use the `course_template/` directory at repo root as the canonical layout:

```
/course.yaml
/modules/
  01-getting-started.md
/assignments/
  A1.md
  A1.rubric.yaml
/assets/
```

- `course.yaml` is the source of truth for metadata.
- Markdown holds content.
- Optional rubric YAML for assessments.
- The validator expects `course.yaml` to use JSON-compatible YAML (valid JSON syntax).

## Similar products / references
- Canvas LMS (inspiration for course organization)
- Notion or Obsidian (linked knowledge / graph mindset)
- Miro or Figma FigJam (infinite canvas)
- Trello or Jira (kanban + task lifecycle)
- GitBook (docs + structured learning content)

## Practical questions to resolve (not in the initial spec)
- What is the data export story for users (CSV/JSON, PDF portfolio, static site)?
- How will privacy work for public/unlisted content (robots.txt, signed URLs, share tokens)?
- How do we handle abandoned courses (archiving, reminders, cold storage)?
- Will the mobile app support offline usage? If yes, what is the conflict strategy?
- How do we handle timezone changes for deadlines and streaks?
- What are the upload limits for evidence (links only vs. file uploads)?
- Will admins need moderation tooling for public courses? (abuse reports, takedown)
- How should AI features be gated to avoid hallucinated syllabus imports?
- What is the plan for rate limiting and OAuth scopes for git provider adapters?
- How will we handle accessibility (keyboard navigation on canvas, screen readers)?

## Feasibility and timing (solo developer estimate)
Assuming one developer with ~6 months experience, building Django backend + Flutter app.

### Best-case MVP (tight scope, minimal UX polish)
- 450–700 hours

### More realistic MVP (integration bugs included)
- 800–1,200 hours

### Rough breakdown
- Auth + user/account + basic UI shell: 60–100h
- Course template schema + parser + validation: 40–80h
- GitHub adapter (read + PR write): 80–140h
- DB models + APIs (courses, versions, discussions, submissions): 80–140h
- Flutter UI (course view, edit, submission, discussion): 120–200h
- Deployment + logging + monitoring + security cleanup: 50–80h

## Potentially impractical (risks)
- Combining calendar + infinite canvas + git-based course authoring in v1 risks scope creep.
- Supporting multiple git providers early (GitHub + Gitea + GitLab) multiplies auth and webhook complexity.
- Rich “portfolio” rendering plus public sharing invites moderation, abuse handling, and privacy complexity.

## Recommended v1 spine (choose one)
- **Git-first**: repo → course → PR edits → profile/portfolio; defer calendar/canvas polish.
- **Planner-first**: calendar/canvas + progress + evidence; treat git links as evidence only.
