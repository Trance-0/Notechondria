# TASKS

Pending version: 0.1

Here is a list of task we need to do now after testing, finishing and solve these bugs in order, and check the item from the list when you are done, ignore the checked items. The following is the list you need to follow:

1. If certain functionality in frontend involves changes in backend, add the backend function in the corresponding module and test them before implementing them in frontend, provide options for hard to implement features.
2. For testing backend, check render-mcp, the api key and database credentials is in the local `sample.test.env`, or `sample.render.env` file.
3. You may Add items to the TODO if
   - You find additional features that I described to you but is not implemented to keep them on track and let me know you get to it.
   - A big task that needs to be decomposed into smaller tasks, and test on each steps.
4. For the bug you fixed on this round, create a new `<Pending-version>.<inc-numeral>.md` in `./docs/` versions, move your finished item (delete the completed item in this file) to this new file, follow the templated defined in previous files.
5. For new features, deleted features, include the detailed descriptions update in `./docs/`
6. **Versioning rule:** On each update, increment the third digit in `./VERSION` (e.g. `0.1.8` -> `0.1.9`). The first two digits (`0.1`) are controlled by humans only — never change them. The `VERSION` file is read by `prepare_env.sh` to tag Docker images as `v<VERSION>.<BUILD_NUMBER>`.
7. Let me know any environment variables need to be updated. After all edits are done, check every test passed. COMMIT and I will push after check.
8. Always finish `**Urgent**` tasks first if exists.
9. PAUSE WHEN CREDIT LIMIT RUNS OUT BEFORE CONTINUE THE NEXT TASK

## Bugs

- [ ] Initial load used offline fallback: Invalid token.
- [ ] OAuth login failed: Account binding requires authentication. Use /api/v1/auth/bind/google/.

## Global reusable components

- [ ]  **Urgent**: I see many components that should be reused but not formulated correctly, for example, 
  - The Sidebar/Navigation is a container that could be reused, so that when you fix the bug in editor app, you don't need to fix the one in portal app, and vice versa.
  - The debug window should be reused between editor and portal app.
  - Login account window should be reused between editor and portal app.
  - The local app preference (currently named as `Editor preferences` in editor app, rename it to `App preferences`) should be reused between editor and portal app.

### Start up animations

- [ ] The current animation don't fits the theme of citric acid cycle, there is no animation for particle changing on each cycle step. Show the process how one chemical becomes the other with the detailed animation (Do not include any text, use structural formula instead).
- [ ] Acetyl-CoA should be represented in structural formula instead of English name.
- [ ] Chemical is bounded and the loading text is always `Loading...`, change the the text to more detailed context, like `Connecting to server`, `Loading public notes data`, etc.
- [ ] Add fade in effects for title `Notechondria` and for detailed context texts on refresh and updates (e.g. `Loading public notes data`).

### Sidebar/Navigation

- [ ] Sync the editor sidebar for the portal sidebar. (Removing title, `wide layout` texts. You may create a list of items/widgets that feed into the `sidebar` class, the `sidebar` should have some properties/functions like `header text` (used in vertical layout), `lower left item` (the `new category` trigger should lives in that))

### Login and account info

- [ ] Full feature parity with editor Settings: API key section (with rotate
  button and MCP endpoint helper), password-change dialog with identity code
  verification, email-change dialog, config file download. As of 0.1.18 the
  Settings module is visible in portal's sidebar and covers the basic
  account/preferences/sync surfaces, but the v0.1.17 editor-only additions
  still need to be ported into `portal_app/lib/modules/settings.dart` — this
  requires syncing client methods, app_shell callback wiring, and the
  `_ApiKeySection` widget.
- [ ] Lock API base URL if user logged in and show tooltip to let user logout before change API base url.
- [ ] In login window, show the api base domain name as subtitle after `Login` title.

### App preferences

### Debug log window

- [ ] Add label for debug level, e.g. `Error`, `Warning`, `Info`, `Debug`. Set debug level to `Debug` by default at this stage.
- [ ] Many information is not complete and don't provide useful information. Instead of `Initial data loaded`, use `Initial <what class>, <what function> data loaded`.
- [ ] Make log output for status and timing for each backend requests in debug log level.
- [ ] Add terminal inputs on bottom of debug log. Add the following function supports
  - `ls` and `cd` to navigate cache folder/directory. (I really hope you organized all the cache configurations correctly, or it will be pain here.)
  - `clear` to clear the debug log.

## Editor

### Note view

- [ ] Allow user to delete local category (except inbox) when no login. Do not sync anything, if they login, always pull, then merge.

#### Search

### Note preview

### Note editor

#### Markdown Editor

##### Plaintext editor

##### Markdown editor

### Editor Settings

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

## Backend

- [ ] I noticed that some data structure is not split cleanly by their function, e.g. The course should have a independent app folder for easy management

### MCP

## Documentation pages

- [ ] ""URGENT"": The backend is written in one long file, which is hard to read and maintain, split it into multiple files categorized by apps in the `backend/` folder (e.g `gptutil`,`notes`,`creator`). With more detailed explanation for each api call with example outputs.
- [ ] ""URGENT"": Pay special attention on how django backend manage the storage of user data and how frontend manages the storage of user data for offline local users. The structure storage of note class, course class, and others.
