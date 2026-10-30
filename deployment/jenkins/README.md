# Jenkins full-stack deployment

The local Docker Jenkins controller builds **GitHub `main`**, triggered by
GitHub push webhooks. It reads `Jenkinsfile` from the remote repository.
Deployment secrets stay on the local build agent. Local checkout files are
not used as pipeline source.

## Current host

- Controller: http://127.0.0.1:8081/ (public URL https://jenkins.trance-0.com/).
- Job: `notechondria`, **Pipeline script from SCM**.
- Git repository: `https://github.com/Trance-0/Notechondria.git`.
- Branch: `*/main`; script path: `Jenkinsfile`; lightweight checkout disabled.
- Build node label: `local-docker`; its workspace is bind-mounted at the same
  absolute path on the host so Docker bind mounts resolve correctly.
- Trigger: **GitHub hook trigger for GITScm polling**.
- Webhook receiver: `https://jenkins.trance-0.com/github-webhook/`.

A separate systemd controller runs at http://127.0.0.1:8080/. Its login,
configuration, and build history are independent. The Docker controller at
:8081 is the webhook deployment target documented here.

## Environment configuration

`local.env` at the repository root is the private reference for this target;
it is ignored by Git and mode 0600. Its Casdoor and GitHub sync settings
reference `prod.env`, while PostgreSQL credentials match the existing local
cluster. Never commit either private env file.

The active agent reads
`/var/lib/jenkins/secrets/notechondria-deploy.env` **inside
`jenkins-local-docker`**. Update it from the reference:

```bash
docker cp local.env jenkins-local-docker:/var/lib/jenkins/secrets/notechondria-deploy.env
docker exec jenkins-local-docker chmod 600 /var/lib/jenkins/secrets/notechondria-deploy.env
```

The pipeline copies this private file into `.env.deploy` in its workspace
and removes the workspace copy in final cleanup. `DEPLOY_ENV_SOURCE` can
select another private agent path. Backend Compose forwards its integration
variables using `ENV_FILE_PATH`; no credentials are embedded in Jenkinsfile.
Keep existing database credentials when deploying over populated volumes.

The local backend uses the existing PostgreSQL and static/media volumes.
`DATABASE_URL` is explicitly empty in Compose to prevent a production URL
from redirecting local migrations. Local uploads use Docker volumes instead
of the production R2 bucket; the same application features remain available.
Do not configure production R2 for local testing: startup clears collected
static files. No database reinitialization is enabled.

Optional missing credentials in the current reference:

- `OPENAI_API_KEY`: needed for AI requests.
- SMTP host, username, password: needed for email delivery.

Casdoor and GitHub App credentials are populated. Browser SSO requires local
callback origins registered with the identity provider; GitHub installation
and push authorization are per-user. Neither browser authorization flow was
verified by the deployment health checks.

## Deployment sequence

1. Jenkins loads Jenkinsfile from GitHub main; checkout in the build workspace
   fetches the remote source. The Git commit is recorded in build provenance.
2. Prepare the private environment and the capped Buildx worker.
3. Run 281 backend tests, each app's smoke suite, and shared local-folder tests.
4. Back up PostgreSQL outside the workspace at
   `/var/lib/jenkins/backups/notechondria/` inside the build agent.
5. Deploy Django, PostgreSQL and backend nginx; build and deploy editor,
   planner and portal sequentially; refresh the gateway.
6. Require success from `/api/v1/handshake/`, all three app routes, compiled
   JS/CanvasKit assets, and configured Casdoor when credentials are provided.

The stack is available at http://localhost:9060/portal/, `/editor/`, and
`/planner/`, with the API under `/api/v1/`. All three apps embed the repository
VERSION and target the local backend. App/backend/nginx and test images use
`v<VERSION>-jenkins.<BUILD_NUMBER>` tags, for example
`notechondria-editor_app:v0.1.203-jenkins.16`. Running containers include the
software version, for example `notechondria-editor-v0.1.203` and
`notechondria-app-v0.1.203`; their version label matches it. PostgreSQL and
gateway nginx retain their own upstream image versions. Compose service and
project names, network aliases, and named data volumes stay stable across
software-version changes. The build stamp is applied after copying the
private env, so stale `latest` or numeric tags cannot override VERSION. Tests and backups gate deployment;
failures stop the pipeline. Persistent volumes and backups survive builds.

The Build resources stage requires at least 12 GB available RAM and creates
`notechondria-local` with an 8 GiB memory cap, four CPU quota, and one parallel
build step. Heavy builds run sequentially with timeouts. Backend containers
are capped at 1 GiB, PostgreSQL at 512 MiB, nginx/app frontends at 128 MiB.
Inspect logs before retrying any failed or five-minute-silent build.

## Restore or configure the remote job

The host helper preserves the existing private env and backs up the old job
XML under ignored `logs/`. It configures SCM and the webhook trigger without
starting a build or copying local source:

```bash
read -r -s -p 'Jenkins admin password: ' JENKINS_PASSWORD
export JENKINS_PASSWORD
python3 deployment/jenkins/configure_docker_job.py
unset JENKINS_PASSWORD
```

Make code changes, commit, and push to GitHub main. Verify the new Jenkins
build says **Started by GitHub push**, checks out the pushed SHA, and finishes
successfully. **Build Now** can retry the remote checkout; it also uses GitHub
main. There is no local source override.

## Native Ubuntu installation

`bash ~/scripts/install-jenkins.sh` invokes the versioned installer. Run as
the normal Ubuntu user with Docker access; the script uses sudo for Java 21,
Jenkins LTS, plugins, and service setup. It preserves existing data and env
files. The managed job is also SCM-based; the native node is labeled
`local-docker`. No deployment starts automatically. Jenkins binds loopback
on :8080; `JENKINS_PORT` can select another verified-free port. The generated
admin password stays at `/var/lib/jenkins/secrets/notechondria-admin-password`.
Point any public webhook tunnel at the intended controller. The installer
does not change FRP configuration.

## Failure diagnosis and verification history

Docker build #10 failed because the backend image omitted the shared API
contract JSON fixtures. `backend/Dockerfile` now includes them. The contract
test explicitly selects its unconfigured Casdoor fixture state so populated
local credentials do not change its expected response. Backend Compose now
forwards integration env variables that were previously dropped.

The earlier system job failed on an unsandboxed local pipeline, an old
workspace ownership mismatch, and different generated database credentials.
Those local-source attempts are historical diagnostics; the deployment job
has been restored to remote SCM per the owner's instruction.

Earlier builds #6 (systemd) and #12 (Docker) proved the test/deployment stages
using snapshots. They do not prove webhook behavior. Their logs remain under
ignored `logs/`. The remote webhook verification is recorded separately in
`docs/LLM_CHECK.md`.

When changing an existing job from inline Pipeline back to SCM, run one
**Build Now** against GitHub to establish checkout/polling state. A webhook
may be received without scheduling while the last run has no SCM state.
After that baseline, push a commit and verify the automatic build cause.
The initial restored SCM build is #13 for revision `2f8dc048`; its checkout
comes from GitHub on both the controller and build agent.

Verified on 2026-10-30: [Docker build #14](http://127.0.0.1:8081/job/notechondria/14/)
was **Started by GitHub push by Trance-0**, checked out
`2e0ba01e95e06b041ecc407c6061e08eab1bc028` from GitHub main, and completed
SUCCESS. All seven containers were healthy, and the running handshake
reported the same commit. Test, backup, frontend-assets and Casdoor checks
passed. Logs remain locally at `logs/jenkins-remote-build-14.log`.
