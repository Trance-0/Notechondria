# Backend Test Plan (Current)

## Scope

Covers model utilities, markdown rendering behavior, and authenticated note access.

## Test suites

1. `creators.tests.CreatorModelTests`
   - profile image path generation
   - verification default values

2. `notes.tests.NoteBlockMarkdownTests`
   - markdown output for code block and quote block

3. `notes.tests.NoteUtilitiesTests`
   - utility safety (`get_object_or_None`)
   - unique ID generation constraints
   - object-level permission checks with `check_is_creator`

4. `notes.tests.NotesViewSmokeTests`
   - `/notes/collections/` redirects anonymous users
   - authenticated user gets page response

5. `gptutils.tests`
   - visual model detection
   - system prompt serialization
   - message body/extras split behavior for long texts

## Run

```bash
python backend/manage.py test --settings=notechondria.settings_test
```
