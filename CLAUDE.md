@AGENTS.md

## Project-scoped rules

### Bark push notifications after commit / before push

If there is any `*.bark.env` file in the project root, treat its
contents as Bark push URLs (one URL per file, possibly multiple
files). After all tests pass and you are ready to push, send a
short progress summary to every Bark URL by POSTing JSON to the
URL without the trailing `/$0` segment:

```bash
curl -sS -X POST <URL_WITHOUT_/$0> \
  -H 'Content-Type: application/json' \
  -d '{"title":"Notechondria 0.1.XX ready to push","body":"<short summary>"}'
```

`*.bark.env` files are covered by `*.env` in `.gitignore` — never
commit them, never echo their contents to logs or commit messages,
and never include them in any PR body. The URL contains a
device-specific secret.

See <https://bark.day.app/> for the Bark API reference. Keep
notifications short (1 line body) so they render on the iOS lock
screen without truncation.
