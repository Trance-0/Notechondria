# TASKS

Here is a list of task we need to do now after testing, finishing and solve these bugs in order, and check the item from the list when you are done, ignore the checked items.

If certain functionality in frontend involves changes in backend, add the backend function in the corresponding module and test them before implementing them in frontend, provide options for hard to implement features.

Add items if you find additional features that I described to you but is not implemented to keep them on track and let me know you get to it.

PAUSE WHEN CREDIT LIMIT RUNS OUT BEFORE CONTINUE THE NEXT TASK

## Editor

- [ ] Now the panel don't redirect or route url for different contents as normal websites do and all link are stored on the same editor route. Is it possible to give different notes different routes, label by their uuid with strict access policy?

### Sidebar/Navigation

- [x] Remove the Notechondria editor title from the sidebar.
- [x] Enable drag and reorder for the categories. (backend: `Course.sort_order` + `POST /api/v1/courses/reorder/`; frontend: `ReorderableListView` in wide sidebar with pinned Inbox)
- [x] Hold categories for editing the category name (course, plan name in future version) and delete the category (show warning before deletion, move all notes to default category, the default "Inbox" category cannot be deleted) keep a simple editor for testing at this stage. Add tooltip for that on hover.
- [x] At bottom of the Category drop down, add a placeholder to create a new category.
- [x] Current drag and update, and hold to edit, add new categories are not implemented in vertical app view. (Replaced PopupMenuButton with Drawer containing ReorderableListView, long-press-to-edit, and "New category" — mirrors wide sidebar)
- [ ] In Edit category, besides category name, add a selector for course icon (select from flutter sources)

### Note view

- [x] Remove three-dot menu button in the card
- [x] Remove the helper text in the card "Course metadata stays editable from the editor details panel"

#### Search

- [x] Implement basic in-note search with case insensitive match, with checkbox for All, or personal notes (backend `scope=all|personal` on `/api/v1/notes/`, frontend checkbox in Learner search bar)

### Note preview

- [x] The display for note header is too small, make appropriate padding on lower subheadings.
- [x] Add options for export markdown.
  - A checkbox include metadata; default to add the header about note metadata (author name, course name, last edit time, creation time, etc.), add selectable to note format, 
  - A checkbox for recursive export; default to false.
  - A selector of export format; default is zip with the following structure
  ```
   - <note> (specified by note name, should be unique)
      - media
          - some-image.png
          - some-image.jpg
          - other-static-resources.mp3
          - some-cited-document.pdf
          - <some-other-referenced-notes-folder> (when recursive export is enabled, only include public notes owned by our site)
              - media
                - ...
              - .metadata (store module, last change, etc, remove if not selected)
              - note-<created_timestamp>.md
          - ...
      - .metadata (store module, last change, etc, remove if not selected)
      - note-<created_timestamp>.md
  ```
  - second is markdown-only only export the pure markdown file (include the metadata as the first line in the file with a yaml header).
- [x] Add additional options for import notes, supports zip and markdown files, reverse the process as above as described. (ZipDecoder path handles recursive archives; YAML frontmatter title/description round-trips back into created notes)
- [x] When clear local cache, should have `Inbox` folder only, but the old templates `Vibe coding 101` etc still remains and there are currently 2 inbox. (Fixed `_clearLocalData` to clear `_localCache`, `_deletedNotes`, reset stats, and re-seed via `_ensureStarterWorkspace()`)
- [x] Category delete is not functional locally (also failed remotely). (Local: notes now remapped to default Inbox via `_remapDraftCourseId`; remote: auto-selects default course after delete; added snackbar feedback. Backend verified with 4 new tests.)
- [x] The display for cloud status will have multiple icons, only three status is needed (offline/online/not synced). (3 states: `cloud_off_outlined` offline, `cloud_upload_outlined` not synced, `cloud_done_outlined` synced)
- [x] Avatar uploaded but not displayed on the editor page now. (Settings page now uses `_RemoteAvatar`; cache-bust on upload via timestamp query param + `imageCache.clear()`)

### Note editor

- [x] In vertical view, title is not correly displayed on iphone machine. (Header now uses LayoutBuilder: narrow <600px stacks title/controls vertically; wide keeps single Row)

#### Markdown Editor

- [x] Should display one red text warning belows the title if user is not following the markdown spec. Only show one line red text warning is enough.
- [x] Full GitHub Flavored Markdown (GFM) is not supported yet, at least the following features are missing
  - [x] details and summary tags
- [x] Access control is broken, a login user should not edit public notes that are not owned by them. (Frontend: `_openViewer` now checks `author.username == currentUsername`; Edit/Delete only shown for owned notes or local drafts)
- [x] Remove the inline/raw version toggle, if user wants to use raw, they can use plain text editor. (Removed `SegmentedButton` and `_liveMarkdownPreview` field; live editor always shows inline mode)
- [ ] Broken html tag may corrupt the markdown sometimes
- [x] `<details>` and `<summary>` are not correctly rendered in the editor. (Fixed `_DetailsBlockSyntax`: relaxed pattern to `^\s{0,3}<details\b`, `canEndBlock: false`, handles single-line blocks and inline `<summary>`, trims body content)
- [ ] Live parsing is not behave as expected, the grey line should display only on hover, and when click, it should create a new empty block
- [ ] Add a lower right add button for inserting attachment (image, file, etc. )

##### Plaintext editor

- [x] Syntax highlighting is not functional (bold for bold, italics for italics, etc. Follows the GFM spec)

##### Markdown editor

- [x] Rename the editor to Live Markdown Editor
- [x] Remove the double column editor for now.
- [x] Live render the sections where user is not editing (like typora). Dynamically allocate and enable full features of GFM. (Inline stacked paragraph editor: each paragraph renders as MarkdownBody until tapped, then swaps into a borderless TextField; thin hairline insert slots between paragraphs add empty blocks. `Raw` escape hatch kept via SegmentedButton.)

##### Block editor

- [x] Remove the top menu for adding blocks (bold, italics, etc.) They should pop in the position when user hover on the intersection between two existing blocks and top, bottom padding areas. (to insert new block in that position)
That means, the block add menu item should be (paragraph, list, enumeration, code, quote, image, dropdown, html embedding, etc.)

- [x] Follows the design for notion
  - [x] Full live markdown editor support, it should be an extension of markdown editor (Block cards now show MarkdownBody preview when inactive; tap to edit, with type-aware markdown composition for headings/code/quotes/links/images)

### Editor Settings

- [x] Disable user change for account name, this shoule be unique and not change on create account(add validation on registration), user may change display name. (Username TextField set to `readOnly: true` with helper text)
- [x] Remove current email editor, setup registration and security policies that one needs to verify old email before changging to new one. Both email needs to be validated before proceeding the change. (Email field removed; profile email passed read-only to API)
- [x] Save editor config to cloud with user, put pull and push as independent subsection and add short description for what those do. (Push/Pull moved into "Sync" subsection with ListTile descriptions)
- [x] Remove auto save in settings. change to click to save and promt user what changed before proceed. (now the auto save is interrupting user input and may save unwanted changes) (Replaced `_scheduleAutoSave` with explicit "Save settings" button + change-summary confirmation dialog)
- [x] Remove configuration section, as the function should be migrated to the login and account info section/Editor Preferences. (merged Download config / Restore templates / Recycle bin / Clear all local data into an "Offline account" row inside Offline preferences)
- [ ] For each section in editor settings (online account (when actually online), editor preference) unify the save button on the lower left of the widget, and cancel button on the lower right, these two buttons should span the row and cancel should be grey when nothing changed. (when cancel is clicked, restore value from remote) If not saved on quit page, default to discard the change.

#### Login and account info

- [x] No save button for now, updated avatar image and motto, email cannot be saved. Put the (configuration section) as subsection of login and account info
- [x] Organize the widgets by their functions, put
  - Online account setting: save account config reset password, logout on the same line
  - Offline account setting: Download config file, Recycle bin, restore templates, clear all local data. (add warning and 3s confirmation before clearing recycle bin and local data)
- [x] Remove clear local cache, I assume that is equivalent to clear all local data.
- [x] On login widgets, remove the helper text "sign in with your email and password... Admin user name also.... admin account". This text is redundant and occupy too much space on mobile view, making no place to fit keyboard.
- [x] Chrome password auto fill is still not supported. Find out why and fix it. (root cause: dialog popped before `TextInput.finishAutofillContext()` fired, so Chrome never saw a completed submission. Call added on successful login.)
- [x] When pull is called after deleting local data, remote data is not downloaded and synchronized. (Added `_loadInitialData()` call after pull completes to refresh remote courses and notes)
- [ ] User avatar setting has duplicated functions, when user click it's own image, it should be preview only. And upload avatar to edit.
- [ ] Change edit username to "Change First name and Last name" (2 text fields on same row)
- [ ] Since we don't allows user name edits, change the username to display only as subtext after the user name.

#### Editor Preferences

- [x] Currently default editor naming is inconsistent.
- [x] Rename the section heading from "offline preferences to "Editor preferences" (Section heading and comment updated in settings.dart)

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

- [x] Currently login session is lost after refresh the webpage, this should be fixed. (Token + profile persisted via `_LocalAppStore.saveSession`; restored on startup with `/auth/session/` validation; cleared on logout)
- [ ] Register windows
  - [x] Username, email, password (with validation, 8 digit minimum with simple measurement for strong password), repeat password (backend: `RegisterSerializer` with username field, 8-char min, uppercase+lowercase+digit/special validation)
  - [ ] Invitation code (implement that in backend, plain sha 256 and compare with the record added in backend admin site) (backend: `InvitationCode` model with SHA-256 hash, auto-hash on save, consume on use; required only when codes exist in DB) Note, the invitation code is separated from the email verification code. The invitation code is used for registering new users only for testing.
  - [ ] (only when invitation code is checked and not used in backend) Enable email verification (60s resend, 6 digit code with expiration, only store hash code in backend), we will set smtp params in environment variables. (backend: 6-digit codes stored as SHA-256 hash via `VerificationCode.generate_code()`, 60s cooldown in `ResendVerificationSerializer`)
  - [x] Register (frontend implementation) (new `_RegisterDialog` with username, email, password, confirm password, invitation code fields; client updated with new signature)
- [x] Implement simple find password
  - [x] only use email for reset password, if no email find on backend, reject the request (backend: `PasswordResetRequestSerializer` rejects unknown emails)
  - [x] Email verification (same as register) (backend: 6-digit hashed codes for password reset too)
  - [x] Reset password, retype and confirm password. (`_PasswordResetDialog` now has confirm password field with match validation)

- [ ] Embed from all setting from the micro services included.
  - Editor settings
  - Planner settings

## Backend

- [x] `.env.example` not given? rename that to `sample.env` to ensure consistency and give a full example environment needed for this project, I will prompt you with current example, or you may see `sample.text.env` if you have it in root dir. (Created `sample.env` with sanitized placeholders; `sample.test.env` kept for CI/dev reference)
- [ ] Edit the admin portal for django, show the ow
- [ ] Create welcome notes for new users showing the functionality of this site, add the welcome note to the template and inbox course.

### MCP

- [ ] Enable fully functional MCP, enable AI to interact with the site when user creates API keys, let it able to access all backend functions that manage the user's data (note operations, user profile, course operations, etc).

## Documentation pages

- [x] Deploy the docs as static rendering for GitHub Pages, map to `*.github.io/docs/`. As wiki for future user and developer guides. (mdBook config in `docs/book.toml` + `docs/SUMMARY.md`; workflow builds with mdBook and deploys to `/docs/` path on gh-pages; landing page updated with docs link)
- [x] Documentation source repo redirects to https://github.com/Nesbitt-bot/Notechondria, need to be Trance-0's main repo (Updated `book.toml` git-repository-url and edit-url-template to Trance-0/Notechondria)
