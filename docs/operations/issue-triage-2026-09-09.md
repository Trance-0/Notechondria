# Issue triage, 2026-09-09

Reviewed all 16 open GitHub issues and their comments against `main`
at `26d21829` (0.1.197). Age alone is not evidence that an issue is fixed.
No issue had sufficient evidence for closure as completed.

Updated the bodies of #4, #5, and #16 to retire the old workstation's
browser/low-memory blocker. Chrome automation is now available on the
current 64 GiB Windows workstation. The requested acceptance tests and
reusable probe scripts remain open; no Activity or storage-isolation
test was performed during the Jenkins investigation.

| Issue | Disposition / remaining work |
| --- | --- |
| [#4 Activity UI verification](https://github.com/Trance-0/Notechondria/issues/4) | Updated stale blocker; deployed Activity acceptance pass remains. |
| [#5 Browser probe layer](https://github.com/Trance-0/Notechondria/issues/5) | Updated stale blocker; no reusable probe workflow or scripts exist. One-off Chrome access does not complete this issue. |
| [#9 MDX](https://github.com/Trance-0/Notechondria/issues/9) | Remains open for parser and sync-write support. |
| [#10 Repository binder](https://github.com/Trance-0/Notechondria/issues/10) | Owner decision on intended binding cardinality; existing backend binding does not complete the selector UI. |
| [#12 Drag to reschedule](https://github.com/Trance-0/Notechondria/issues/12) | Event dragging and 15-minute snap remain; an existing now indicator is only partial completion. Missing SDK on a previous host is not a product decision. |
| [#14 Developer menu](https://github.com/Trance-0/Notechondria/issues/14) | Planner/portal settings expose some integrations, but that does not implement the requested developer menu. |
| [#15 Experimental registry](https://github.com/Trance-0/Notechondria/issues/15) | Existing GitHub data-sync card is not proof that the requested course-sync registry entry exists. |
| [#16 Storage isolation](https://github.com/Trance-0/Notechondria/issues/16) | Updated stale blocker; automated cross-app storage acceptance test still absent. |
| [#17 Planner localization](https://github.com/Trance-0/Notechondria/issues/17) | Partially localized; Activity and course modules still contain English-only UI strings. |
| [#18 Shared localization](https://github.com/Trance-0/Notechondria/issues/18) | Keep open pending the requested full component/dialog audit. |
| [#19 Planner starter](https://github.com/Trance-0/Notechondria/issues/19) | Owner decision: retain sample course or use Inbox/scratchpad. Current seed is still `Starter planning course`. |
| [#20 Coach marks](https://github.com/Trance-0/Notechondria/issues/20) | Owner decision: retain deferred work or close as not planned. |
| [#21 Casdoor cleanup](https://github.com/Trance-0/Notechondria/issues/21) | Migration document still describes the original plan; remaining cleanup is not demonstrably complete. Preserve permanent local fallback login. |
| [#23 Casdoor configuration docs](https://github.com/Trance-0/Notechondria/issues/23) | Redirect table exists, but docs still say JWT rather than the requested JWT-Custom/password-field configuration; actual registered settings need verification. |
| [#25 MCP distribution](https://github.com/Trance-0/Notechondria/issues/25) | No verified PyPI publication evidence collected; do not close on packaging/docs alone. |
| [#29 App releases](https://github.com/Trance-0/Notechondria/issues/29) | Only portal release workflow exists. Owner decision: combined release or separate app tags. |

The owner was asked about #10, #19, #20, and #29. No specific decision
was supplied during this review; these remain open without inventing a
new blocked label. A scheduled browser CI job and PyPI publication also
remain separate work, outside the Jenkins repair.
