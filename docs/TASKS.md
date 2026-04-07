# TASKS

Pending version: 0.1

Here is a list of task we need to do now after testing, finishing and solve these bugs in order, and check the item from the list when you are done, ignore the checked items.

If certain functionality in frontend involves changes in backend, add the backend function in the corresponding module and test them before implementing them in frontend, provide options for hard to implement features.

For testing backend, check render-mcp, the api key and database credentials is in the local `sample.test.env`, or `sample.render.env` file.

Add items if

- You find additional features that I described to you but is not implemented to keep them on track and let me know you get to it.
- A big task that needs to be decomposed into smaller tasks, and test on each steps.

For the bug you fixed on this round, create a new `<Pending-version>.<inc-numeral>.md` in ./docs/versions, move your finished item (delete the completed item in this file) to this new file, follow the templated defined in previous files.

Let me know any environment variables need to be updated. After all edits are done, check every test passed. COMMIT and I will push after check.

Always finish urgent tasks first if exists.

PAUSE WHEN CREDIT LIMIT RUNS OUT BEFORE CONTINUE THE NEXT TASK

## Editor

### Urgent tasks

- [ ] Now the panel don't redirect or route url for different contents as normal websites do and all link are stored on the same editor route. Is it possible to give different notes different routes, label by their uuid with strict access policy (All site viewer can view public notes, but only note owner can edit. Registered user can cite, comment (set note type as comment with source. It should not be deleted(but will be private) when the source note is deleted (The detailed comment section will be displayed on Planner App)), etc)? Implement the function so that every distinct note have their unique url. You also need to add/rewire backend function for creating uuid I assume.

### Sidebar/Navigation

- [ ] In Edit category, besides category name, add a selector for course icon (select from flutter sources)

### Note view

#### Search

### Note preview

### Note editor

- [ ] Add a lower right add button (the same as add notes) for inserting attachment (image, file, etc.) And create code embedding for rendering the imported contents. in both editors. Set max size of the file to be 20MB and create backend services handling the file upload/recycling if resource is not used. Store them in node media folder defined before.

#### Markdown Editor

##### Plaintext editor

##### Markdown editor

### Editor Settings

#### Login and account info

#### Editor Preferences

## Planner

- [ ] Remove the front page module, this should be added in portal app with recommendation algorithm.

### Course list

- [ ] Make card like the one on Canvas, where upper half is preview image (if image not set, use theme color filled, for template course, we have feature images included) Then the card lower shows the related info.

#### Course view

### Activity view

### Planner Settings

- [ ] Not migrated yet, continue migration

## Portal

- [ ] Set the root url to portal, that is, `*.github.io/Notechondria/` should be directed to the portal app

### Front page

- [ ] Migrate from old front page, Keep it as the universal front page, display recent public courses, (use default ones for now.)
- [ ] Update heatmap statistics

### Course

- [ ] Embed from /planner/Course view

### Learner

- [ ] Embed from /editor/Note view

### Activity

- [ ] Embed from /planner/Activity view

### Settings

- [ ] Register windows
  - [x] Username, email, password (with validation, 8 digit minimum with simple measurement for strong password), repeat password (backend: `RegisterSerializer` with username field, 8-char min, uppercase+lowercase+digit/special validation)
  - [ ] Invitation code (implement that in backend, plain sha 256 and compare with the record added in backend admin site) (backend: `InvitationCode` model with SHA-256 hash, auto-hash on save, consume on use; required only when codes exist in DB) Note, the invitation code is separated from the email verification code. The invitation code is used for registering new users only for testing.
  - [ ] (only when invitation code is checked and not used in backend) Enable email verification (60s resend, 6 digit code with expiration, only store hash code in backend), we will set smtp params in environment variables. (backend: 6-digit codes stored as SHA-256 hash via `VerificationCode.generate_code()`, 60s cooldown in `ResendVerificationSerializer`)
  - [x] Register (frontend implementation) (new `_RegisterDialog` with username, email, password, confirm password, invitation code fields; client updated with new signature)

- [ ] Embed from all setting from the micro services included.
  - Editor settings
  - Planner settings

## Backend

- [ ] Edit the admin portal for django, show the ow
- [ ] Create welcome notes for new users showing the functionality of this site, add the welcome note to the template and inbox course.

### MCP

- [ ] Enable fully functional MCP, enable AI to interact with the site when user creates API keys, let it able to access all backend functions that manage the user's data (note operations, user profile, course operations, etc).

## Documentation pages

- [ ] New version is added in doc, update the docs descriptions.
