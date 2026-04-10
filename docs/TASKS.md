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

- [x] Create startup animation. Repeating Citric acid cycle (part of respiration process). You may need to check for the detail for how the chemicals are loaded and cycled. Make a simple flutter animation to demonstrate that, and make smooth quit when frontend resources are loaded or timeout (set to 10 seconds Max).
  - [x] Remove the English name for the chemicals, let the chemical can move out of the screen (anchor with nodes on the cycle) instead of always staying in the screen.
  - [x] Change the particle effects into random chemicals structural formula that might present in the citric acid cycle environment rather than just plain nodes. (with random rotation)

## Editor

### Sidebar/Navigation

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
- [x] Github and Google account binding for existing user should not change the username or email for existing accounts.
- [x] API key (and the rotate button) should be placed directly above the connected accounts setting after user login. Currently the api key is not visible. And also add the helper text to show the mcp endpoint to the user.

#### Editor Preferences

## Planner

### Lerner view

- [ ] List user's notes in each expandible folder grouped by their categories (course), use lazy loading and default chronological order (most recent on top). Default to expand all.

### Course view

- [ ] Make card like the one on Canvas, where upper half is preview image (if image not set, use theme color filled, for template course, we have feature images included) Then the card lower shows the related info.

#### Course detail

- [ ] Implement the module and discussion board in each module, allow user to add the module and discussion board if the own the course. 

### Activity view

- [ ] Implement the activity view, enable user to import their google calender event or ics file, when hold the add button.
- [ ] Unable to subscribe event from google calendar sharing links. caught

``` bash
main.dart.js:1438 grm ERROR [iterable] ░░ No message or displaying the same message
write @ Grammarly.js:2
handleEvent @ Grammarly.js:2
_logMessage @ Grammarly.js:2
error @ Grammarly.js:2
error @ Grammarly.js:2
showIPM @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
v @ Grammarly.js:2
m @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
s @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
g @ Grammarly.js:2
c @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
g @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
m @ Grammarly.js:2
S @ Grammarly.js:2
_subscribe @ Grammarly.js:2
UNSAFE_componentWillReceiveProps @ Grammarly.js:2
aa @ Grammarly.js:2
ka @ Grammarly.js:2
wl @ Grammarly.js:2
_c @ Grammarly.js:2
mc @ Grammarly.js:2
fc @ Grammarly.js:2
ac @ Grammarly.js:2
Hr @ Grammarly.js:2
tc @ Grammarly.js:2
enqueueSetState @ Grammarly.js:2
v.setState @ Grammarly.js:2
_handleValue @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
t.next @ Grammarly.js:2
t.next @ Grammarly.js:2
_onSourceValues @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
t.next @ Grammarly.js:2
t.next @ Grammarly.js:2
_onSourceValue @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
t.next @ Grammarly.js:2
t.next @ Grammarly.js:2
set @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
_disposeIntegrations @ Grammarly.js:2
V._disposeOnRemovedFields @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
t.next @ Grammarly.js:2
next @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
v @ Grammarly.js:2
m @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
childList
bgo @ main.dart.js:1438
b3Z @ main.dart.js:1520
aKP @ main.dart.js:44487
aAu @ main.dart.js:40015
KB @ main.dart.js:85929
(anonymous) @ main.dart.js:86412
(anonymous) @ main.dart.js:5421
$2 @ main.dart.js:48244
x @ main.dart.js:5407
auI @ main.dart.js:86422
lK @ main.dart.js:86406
(anonymous) @ main.dart.js:86494
(anonymous) @ main.dart.js:5421
$2 @ main.dart.js:48244
x @ main.dart.js:5407
aLG @ main.dart.js:86498
d5 @ main.dart.js:86490
aAy @ main.dart.js:87296
Lz @ main.dart.js:87162
Fc @ main.dart.js:90471
anZ @ main.dart.js:90774
(anonymous) @ main.dart.js:4224
a6 @ main.dart.js:56632
O0 @ main.dart.js:91991
a5D @ main.dart.js:92099
(anonymous) @ main.dart.js:4224
bpu @ main.dart.js:5564
bq5 @ main.dart.js:5566
$1 @ main.dart.js:48185
childList
$1 @ main.dart.js:48192
b94 @ main.dart.js:5571
aW3 @ main.dart.js:5650
h6 @ main.dart.js:5583
a3U @ main.dart.js:56997
aG8 @ main.dart.js:56973
md @ main.dart.js:57061
aIt @ main.dart.js:57054
a_D @ main.dart.js:57048
RW @ main.dart.js:57039
MJ @ main.dart.js:57037
asm @ main.dart.js:57025
(anonymous) @ main.dart.js:4225
qd @ main.dart.js:1092
aNF @ main.dart.js:40833
(anonymous) @ main.dart.js:4226
uG @ main.dart.js:40898
$1 @ main.dart.js:41125
$1 @ main.dart.js:41114
$1 @ main.dart.js:40901
JK @ main.dart.js:48965
$1 @ main.dart.js:48981
bnL @ main.dart.js:7617
(anonymous) @ main.dart.js:7608Understand this error
main.dart.js:43988 grm ERROR [iterable] ░░ No message or displaying the same message
write @ Grammarly.js:2
handleEvent @ Grammarly.js:2
_logMessage @ Grammarly.js:2
error @ Grammarly.js:2
error @ Grammarly.js:2
showIPM @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
v @ Grammarly.js:2
m @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
s @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
g @ Grammarly.js:2
c @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
g @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
m @ Grammarly.js:2
S @ Grammarly.js:2
_subscribe @ Grammarly.js:2
UNSAFE_componentWillMount @ Grammarly.js:2
la @ Grammarly.js:2
ka @ Grammarly.js:2
wl @ Grammarly.js:2
_c @ Grammarly.js:2
mc @ Grammarly.js:2
fc @ Grammarly.js:2
ac @ Grammarly.js:2
Hr @ Grammarly.js:2
tc @ Grammarly.js:2
enqueueSetState @ Grammarly.js:2
v.setState @ Grammarly.js:2
_handleValue @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
t.next @ Grammarly.js:2
t.next @ Grammarly.js:2
_onSourceValues @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
t.next @ Grammarly.js:2
t.next @ Grammarly.js:2
_onSourceValues @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
t.next @ Grammarly.js:2
t.next @ Grammarly.js:2
set @ Grammarly.js:2
updateState @ Grammarly.js:2
updateState @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
t._execute @ Grammarly.js:2
t.execute @ Grammarly.js:2
t.flush @ Grammarly.js:2
setInterval
setInterval @ Grammarly.js:2
t.requestAsyncId @ Grammarly.js:2
t.schedule @ Grammarly.js:2
e.schedule @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
v @ Grammarly.js:2
m @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
t._subscribe @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
t._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
s @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
_subscribeToIterablePopup @ Grammarly.js:2
Ne @ Grammarly.js:2
_render @ Grammarly.js:2
_delayedStart @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
Promise.then
ss @ Grammarly.js:2
y @ Grammarly.js:2
createFieldIntegration @ Grammarly.js:2
_setFieldIntegration @ Grammarly.js:2
_initInitialFieldIntegration @ Grammarly.js:2
h @ Grammarly.js:2
b @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e.next @ Grammarly.js:2
t._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
t._subscribe @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
t._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
e._subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
t @ Grammarly.js:2
e.decorate @ Grammarly.js:2
M @ Grammarly.js:2
execute @ Grammarly.js:2
_executeIntegrationRuleMatch @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
v @ Grammarly.js:2
V._initializeOnNewField @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
e._trySubscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
o @ Grammarly.js:2
e.subscribe @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
t._execute @ Grammarly.js:2
t.execute @ Grammarly.js:2
t.flush @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
Promise.then
c @ Grammarly.js:2
setImmediate @ Grammarly.js:2
t.requestAsyncId @ Grammarly.js:2
t.schedule @ Grammarly.js:2
e.schedule @ Grammarly.js:2
i @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
(anonymous) @ Grammarly.js:2
a._next @ Grammarly.js:2
t.next @ Grammarly.js:2
t @ Grammarly.js:2
ml @ main.dart.js:43988
Bq @ main.dart.js:44081
wC @ main.dart.js:44043
Rk @ main.dart.js:44228
aBf @ main.dart.js:44543
ls @ main.dart.js:44452
aKP @ main.dart.js:44521
aAu @ main.dart.js:40015
KB @ main.dart.js:85929
(anonymous) @ main.dart.js:86412
(anonymous) @ main.dart.js:5421
$2 @ main.dart.js:48244
x @ main.dart.js:5407
auI @ main.dart.js:86422
lK @ main.dart.js:86406
(anonymous) @ main.dart.js:86494
(anonymous) @ main.dart.js:5421
$2 @ main.dart.js:48244
x @ main.dart.js:5407
aLG @ main.dart.js:86498
d5 @ main.dart.js:86490
kl @ main.dart.js:86491
OI @ main.dart.js:87322
Fc @ main.dart.js:90484
anZ @ main.dart.js:90774
(anonymous) @ main.dart.js:4224
a6 @ main.dart.js:56632
O0 @ main.dart.js:91991
a5D @ main.dart.js:92099
(anonymous) @ main.dart.js:4224
bpu @ main.dart.js:5564
bq5 @ main.dart.js:5566
$1 @ main.dart.js:48185
childList
$1 @ main.dart.js:48192
b94 @ main.dart.js:5571
aW3 @ main.dart.js:5650
h6 @ main.dart.js:5583
a3U @ main.dart.js:56997
aG8 @ main.dart.js:56973
md @ main.dart.js:57061
aIt @ main.dart.js:57054
a_D @ main.dart.js:57048
RW @ main.dart.js:57039
MJ @ main.dart.js:57037
asm @ main.dart.js:57025
(anonymous) @ main.dart.js:4225
qd @ main.dart.js:1092
aNF @ main.dart.js:40833
(anonymous) @ main.dart.js:4226
uG @ main.dart.js:40898
$1 @ main.dart.js:41125
$1 @ main.dart.js:41114
$1 @ main.dart.js:40901
JK @ main.dart.js:48965
$1 @ main.dart.js:48981
bnL @ main.dart.js:7617
(anonymous) @ main.dart.js:7608Understand this error
4main.dart.js:6430 Uncaught Error
    at Object.i (main.dart.js:4071:20)
    at main.dart.js:114994:34
    at aWp.a (main.dart.js:5421:63)
    at aWp.$2 (main.dart.js:48244:14)
    at Object.x (main.dart.js:5407:10)
    at LL.aBy (main.dart.js:115001:10)
    at LL.vt (main.dart.js:114989:23)
    at LL.aBx (main.dart.js:114990:22)
    at tear_off.$2 (main.dart.js:4226:67)
    at main.dart.js:117659:16
```

- [ ] Add a confirmation page for imported calendar (show few details of the imported item, enable zip import for local import and auto parse the ical file).


### Planner Settings

- [ ] Not migrated yet (there is no setting page in this version at all, not in sidebar), continue migration

## Portal

- [ ] Set the root url to portal, that is, `*.github.io/Notechondria/` should be directed to the portal app
- [ ] For sidebar, add items (Front page, Course, Learner, Activity, and Settings)

### Front page

- [ ] Migrate from old front page, Keep it as the universal front page, display recent public courses, (use default ones for now.)
- [ ] Update heatmap statistics

### Course

- [ ] Embed from /planner/Course view

### Learner

- [ ] Embed from /editor/Note view

### Activity

- [ ] Embed from /planner/Activity view

### Portal Settings

- [ ] Embed from all setting from the micro services included.
  - Editor settings
  - Planner settings

## Backend

- [ ] Create welcome notes for new users showing the functionality of this site, add the welcome note to the template and inbox course. (modify the current registered starter course to just one welcome note in inbox.)

### MCP

## Documentation pages

- [ ] New `versions` is added in doc, update the docs descriptions and include the contents for each version updates in docs.
