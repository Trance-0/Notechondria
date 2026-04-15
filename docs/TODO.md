# TASKS

Pending version: 0.1

Here is a list of task we need to do now after testing, finishing and solve these bugs in order, and check the item from the list when you are done, ignore the checked items.

If certain functionality in frontend involves changes in backend, add the backend function in the corresponding module and test them before implementing them in frontend, provide options for hard to implement features.

For testing backend, check render-mcp, the api key and database credentials is in the local `sample.test.env`, or `sample.render.env` file.

Add items if

- You find additional features that I described to you but is not implemented to keep them on track and let me know you get to it.
- A big task that needs to be decomposed into smaller tasks, and test on each steps.

For the bug you fixed on this round, create a new `<Pending-version>.<inc-numeral>.md` in ./docs/versions, move your finished item (delete the completed item in this file) to this new file, follow the templated defined in previous files.

**Versioning rule:** On each update, increment the third digit in `./VERSION` (e.g. `0.1.8` -> `0.1.9`). The first two digits (`0.1`) are controlled by humans only — never change them. The `VERSION` file is read by `prepare_env.sh` to tag Docker images as `v<VERSION>.<BUILD_NUMBER>`.

Let me know any environment variables need to be updated. After all edits are done, check every test passed. COMMIT and I will push after check.

Always finish `> Urgent` tasks first if exists.

PAUSE WHEN CREDIT LIMIT RUNS OUT BEFORE CONTINUE THE NEXT TASK

> Urgent

## Editor

### Sidebar/Navigation

### Note view

#### Search

### Note preview

### Note editor

#### Markdown Editor

##### Plaintext editor

##### Markdown editor

### Editor Settings

#### Login and account info

#### Editor Preferences

## Planner

### Lerner view

### Course view

#### Course detail

### Activity view

### Planner Settings

## Portal

### Front page

### Course

### Learner

### Activity

### Portal Settings

- [ ] Full feature parity with editor Settings: API key section (with rotate
  button and MCP endpoint helper), password-change dialog with identity code
  verification, email-change dialog, config file download. As of 0.1.18 the
  Settings module is visible in portal's sidebar and covers the basic
  account/preferences/sync surfaces, but the v0.1.17 editor-only additions
  still need to be ported into `portal_app/lib/modules/settings.dart` — this
  requires syncing client methods, app_shell callback wiring, and the
  `_ApiKeySection` widget.

## Backend

### MCP

## Documentation pages
