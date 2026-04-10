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

- [x] Start migration of static file storage to Cloudflare R2, simplify the deployment process for backend and ensure the persistent storage.
  - [x] Add additional instructions for setting up Cloudflare R2 when deploying the backend with render to ensure the static assets are uploaded and accessible.
  - [x] Rewire the backend to use Cloudflare R2 for static assets if the credentials are provided when deploying the backend with render. Raise an error if the credentials are not provided. Otherwise, when deploying the backend with docker compose, use the persistent volume and nginx for cdn delivery.
  - [x] Add the necessary items and credential updates to `sample.render.env`. I will fill them later. be sure to start the var name with `CLOUDFLARE_R2_` to avoid conflict with other env vars. Put them together as a new section.
- [x] Create startup animation. Repeating Citric acid cycle (part of respiration process). You may need to check for the detail for how the chemicals are loaded and cycled. Make a simple flutter animation to demonstrate that, and make smooth quit when frontend resources are loaded or timeout (set to 10 seconds Max).
  - [x] The animation don't cover the whole screen (the sidebar is not covered). The animation should be full screen.
  - [x] Slow down the animation a bit, it is too fast now. Remote the 'citric acid cycle' title.
  - [x] Replaced English chemical names with structural formula representations (organic acid structures, not benzene rings — Krebs cycle metabolites are small organic acids).
  - [x] When editor/planner/portal is opened, start the animation.
  - [x] The animation text is too small, Try to make the animation rotates (citric acid cycle) axis at left center of the screen. And show each step by rotating the cycle to the middle of the screen. Align all text horizontally (Do not rotate the text, just move the text along the circle).

## Editor

### Sidebar/Navigation

- [x] In Edit category, besides category name, add a selector for course icon (select from flutter sources)

### Note view

- [x] In vertical view, the navbar item, where shows `Notechondria Editor` should be removed and replace with current folder name `Inbox`, `All notes`, etc.
- [x] Implement lazy loading for the note list, do not load all notes at once. Remove the load more button, activate the lazy loading on scroll to bottom.
- [x] Note that currently the offline ui will create two inbox folder that cannot be deleted.
- [x] Directly remove the delete button for the default `inbox` folder. Replace with helper text that it cannot be deleted.

#### Search

### Note preview

### Note editor

- [x] Add a lower right add button (the same as add notes) for inserting attachment (image, file, etc.) And create code embedding for rendering the imported contents. in both editors. Set max size of the file to be 20MB and create backend services handling the file upload/recycling if resource is not used. Store them in node media folder defined before.

#### Markdown Editor

##### Plaintext editor

##### Markdown editor

### Editor Settings

#### Login and account info

- [x] Google Chrome password manager is still not detecting the login widget and auto fill, find out why and fix it.

#### Editor Preferences

## Planner

- [x] Remove the front page module, this should be added in portal app with recommendation algorithm.

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

- [x] Register windows
  - [x] First, check for Invitation code (implement that in backend, plain sha 256 and compare with the record added in backend admin site) (backend: `InvitationCode` model with SHA-256 hash, auto-hash on save, consume on use; required only when codes exist in DB) Note, the invitation code is separated from the email verification code. The invitation code is used for registering new users only for testing.
  - [x] back and confirm button (when confirm is clicked, verify the invitation code and move to the next window if successful)
  - [x] After invitation code is verified, Select one from the three: email, google, github
  - [x] When user selects google or github, show their corresponding redirect and implement that
  - [x] When user selects email, show the following form
    - [x] Input fields in the following order: Username (verify be distinct)
    - [x] Email, on the same row (email verification send button, verification),
    - [x] (only when invitation code is checked and not used in backend) Enable email verification (60s resend, 6 digit code with expiration, only store hash code in backend), we will set smtp params in environment variables. (backend: 6-digit codes stored as SHA-256 hash via `VerificationCode.generate_code()`, 60s cooldown in `ResendVerificationSerializer`)
    - [x] password, (with validation, 8 digit minimum with simple measurement for strong password), repeat password (backend: `RegisterSerializer` with username field, 8-char min, uppercase+lowercase+digit/special validation)
    - [x] Back, and register (frontend implementation) (new `_RegisterDialog` with username, email, password, confirm password, invitation code fields; client updated with new signature)

> Urgent

- [x] Add registration via google, use google oauth2 api (env variables are defined in `sample.text.env`, be sure to verify on the backend and capture the callback url from google redirect is on backend, be sure to take user back to frontend app after successful login/register. Ask for appropriate data like email, username from google to create user profiles.)
- [x] Add registration via Github, use Github App api (env variables are defined in `sample.text.env`, be sure to verify on the backend and capture the callback url from github redirect is on backend, and also handle the webhook post from github with verifications, be sure to take user back to frontend app after successful login/register. Ask for appropriate data like email, username from google to create user profiles.)
- [x] Allow existing users to bind their social accounts and login using them, currently support github and google accounts. (put in ui for the after login, show their binding accounts belows the social link (one line for google, one line for github. If no binding account, show the button to trigger the binding process (Online account settings widget), if user has binding accounts, show the button to trigger switch binding third party accounts))
  - [x] Backend is not redirecting the results properly. It should render a static display show if the user has binding accounts successfully or not. And the binding status should be updated in the user profile if binding is successful on the backend. This also holds for google and github accounts. And register pages as well.
- [x] Implement login via third party services (Github, Google) reject, if the account is not registered. Show the error window for user to register account first.
- [x] Add the necessary items and credential updates to `sample.render.env`

- [ ] Embed from all setting from the micro services included.
  - Editor settings
  - Planner settings

## Backend

- [ ] Create welcome notes for new users showing the functionality of this site, add the welcome note to the template and inbox course. (modify the current registered starter course to just one welcome note in inbox.)

### MCP

- [x] Add the api key field(read-only) after `motto` field of user settings. Add rotation button after the api field to generate new api key, the api key should be only visible in front end after user click rotate and the backend should only store the hash of the api key only. (frontend api key is 32 digit hex string)
  - Backend done: `api_key_hash`/`api_key_prefix` on Creator model, `RotateApiKeyApiView`, `ApiKeyAuthentication` DRF backend. Frontend UI deferred (backend-only focus this version).
- [x] Enable fully functional MCP, enable AI to interact with the site using the user api key, let it able to access all backend functions that manage the user's data (note operations, user profile, course operations, etc). It should fully on backend.
  - Backend done: `mcp` Django app with MCP 2025-03-26 spec, Streamable HTTP transport, 23 tools (profile, notes, courses, activity, planner, versions, attachments).

## Documentation pages

- [ ] New `versions` is added in doc, update the docs descriptions and include the contents in docs.
