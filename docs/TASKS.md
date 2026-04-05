# TASKS

Here is a list of task we need to do now after testing, finishing and solve these bugs in order, and check the item from the list when you are done, ignore the checked items.

If certain functionality in frontend involves changes in backend, add the backend function in the corresponding module and test them before implementing them in frontend, provide options for hard to implement features.

Add items if you find additional features that I described to you but is not implemented to keep them on track and let me know you get to it.

PAUSE WHEN CREDIT LIMIT RUNS OUT BEFORE CONTINUE THE NEXT TASK

## Editor

### Sidebar/Navigation

- [x] Remove the Notechondria editor title from the sidebar.
- [x] Enable drag and reorder for the categories. (backend: `Course.sort_order` + `POST /api/v1/courses/reorder/`; frontend: `ReorderableListView` in wide sidebar with pinned Inbox)
- [x] Hold categories for editing the category name (course, plan name in future version) and delete the category (show warning before deletion, move all notes to default category, the default "Inbox" category cannot be deleted) keep a simple editor for testing at this stage. Add tooltip for that on hover.
- [x] At bottom of the Category drop down, add a placeholder to create a new category.

### Note view

- [x] Remove three-dot menu button in the card
- [x] Remove the helper text in the card "Course metadata stays editable from the editor details panel"

#### Search

- [x] Implement basic in-note search with case insensitive match, with checkbox for All, or personal notes (backend `scope=all|personal` on `/api/v1/notes/`, frontend checkbox in Learner search bar)

### Note preview

- [ ] In vertical view, title is not correly displayed on iphone machine.
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

#### Markdown Editor

- [x] Should display one red text warning belows the title if user is not following the markdown spec. Only show one line red text warning is enough.
- [x] Full GitHub Flavored Markdown (GFM) is not supported yet, at least the following features are missing
  - [x] details and summary tags

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
  - [ ] Full live markdown editor support, it should be an extension of markdown editor (pending Typora-style live rendering)

### Editor Settings

- [x] Remove configuration section, as the function should be migrated to the login and account info section/Editor Preferences. (merged Download config / Restore templates / Recycle bin / Clear all local data into an "Offline account" row inside Offline preferences)

#### Login and account info

- [x] No save button for now, updated avatar image and motto, email cannot be saved. Put the (configuration section) as subsection of login and account info
- [x] Organize the widgets by their functions, put
  - Online account setting: save account config reset password, logout on the same line
  - Offline account setting: Download config file, Recycle bin, restore templates, clear all local data. (add warning and 3s confirmation before clearing recycle bin and local data)
- [x] Remove clear local cache, I assume that is equivalent to clear all local data.
- [x] On login widgets, remove the helper text "sign in with your email and password... Admin user name also.... admin account". This text is redundant and occupy too much space on mobile view, making no place to fit keyboard.
- [x] Chrome password auto fill is still not supported. Find out why and fix it. (root cause: dialog popped before `TextInput.finishAutofillContext()` fired, so Chrome never saw a completed submission. Call added on successful login.)

#### Editor Preferences

- [x] Currently default editor naming is inconsistent.

## Planner

- [ ] Remove the front page module, this should be added in portal app with recommendation algorithm.

### Course list

- [ ] Make card like the one on Canvas, where upper half is preview image (if image not set, use theme color filled, for template course, we have feature images included) Then the card lower shows the related info.

#### Course view

### Activity view

### Planner Settings

- [ ] Not migrated yet

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

- [ ] Currently login session is lost after refresh the webpage, this should be fixed.
- [ ] Register
  - [ ] Username, email, password (with validation, 8 digit minimum with simple measurement for strong password), repeat password
  - [ ] Invitation code (implement that in backend, plain sha 256 and compare with the record added in backend admin site)
  - [ ] (only when invitation code is in backend)Enable email verification (60s resend, 6 digit code with expiration, only store hash code in backend), we will set smtp params in environment variables.
  - [ ] Register
- [ ] Implement simple find password
  - [ ] only use email for reset password, if no email find on backend, reject the request
  - [ ] Email verification (same as register)
  - [ ] Reset password, retype and confirm password.

- [ ] Embed from all setting from the micro services included.
  - Editor settings
  - Planner settings

## Backend

- `.env.example` not given? rename that to `sample.env` to ensure consistency and give a full example environment needed for this project, I will prompt you with current example, or you may see `sample.text.env` if you have it in root dir.

### MCP

- [ ] Enable fully functional MCP, enable AI to interact with the site when user creates API keys, let it able to access all backend functions that manage the user's data (note operations, user profile, course operations, etc).

## Documentation pages

- [ ] Deploy the docs as static rendering for GitHub Pages, map to `*.github.io/docs/`. As wiki for future user and developer guides.
