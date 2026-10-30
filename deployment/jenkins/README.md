# Jenkins full-stack deployment

This target uses Jenkins to test and deploy the full stack:
- Django backend
- PostgreSQL database
- backend nginx
- editor frontend
- planner frontend
- portal frontend
- root gateway nginx

## Ubuntu installation

The home-directory scaffold on this host invokes the versioned installer:

```bash
bash ~/scripts/install-jenkins.sh
```

Run as your normal Ubuntu user. The script requests sudo, installs Java 21
and Jenkins LTS using the official signed apt repository, verifies the plugin
manager checksum, installs required plugins, and creates the `notechondria`
pipeline. Docker Engine and Compose must already work for that user; existing
Docker applications are preserved. Both amd64 and arm64 hosts are supported.

Jenkins listens at **http://127.0.0.1:8080**. Sign in as `admin`; read the
password locally from `/var/lib/jenkins/secrets/notechondria-admin-password`.
Passwords are not printed in install logs. The application gateway uses port
9060. Override an occupied Jenkins port with `JENKINS_PORT=8081` before the
install command.

Rerunning preserves generated passwords, deployment settings, jobs' build
history, databases, and media. It refreshes plugins and the managed job
definition, then restarts Jenkins. This is installation/reconfiguration,
not a purge of an existing Jenkins home. Jenkins runs as the invoking user
so it can read the trusted checkout and use that user's Docker permissions.
Use this controller only for trusted project pipelines.

## Local workflow

Open `/job/notechondria/` and select **Build Now** after installation. No
deployment is started automatically by the installer.

1. Copy Git-visible source into a clean workspace, excluding ignored files,
   `.env` files, private keys, symlinks, and Git metadata. Uncommitted source
   fixes are included. `LOCAL_SOURCE_DIR` defaults to this checkout.
2. Copy `/var/lib/jenkins/secrets/notechondria-deploy.env` into the workspace.
3. Run backend tests, then each frontend smoke-test image sequentially.
4. Back up PostgreSQL to `/var/lib/jenkins/backups/notechondria`.
5. Deploy backend, each frontend with a distinct image tag and base path,
   and finally the gateway. Services restart after Docker restarts.
6. Require HTTP success from `/api/v1/handshake/`, `/editor/`, `/planner/`,
   and `/portal/` before Jenkins can report success.

A failed test or backup blocks deployment. Automatic database reinitialization
is disabled. Backups remain outside workspaces and build-history retention.
The generated deployment env contains random database, Django, and app-admin
passwords; edit it locally to configure OAuth, email, or an existing database.
Do not replace existing database credentials with new values on a populated
volume. Jenkins removes the workspace env in its final cleanup.

Frontend Docker build context is `frontend/`, which includes the sibling
`notechondria_shared` path dependency; use `-f frontend/editor_app/Dockerfile`
when building an app manually. Base images support native ARM64.

## Copy-paste diagnostics

The installer saves a private per-run log under
`~/.local/state/jenkins-install/` and emits a delimited diagnostic block on
failure. Logs remain on disk for local inspection. To collect a fresh report:

```bash
bash ~/scripts/debug-jenkins.sh
```

The report includes service state, listening ports, Java/Jenkins package
versions, recent redacted Jenkins journal entries, Docker version, and
Notechondria container state. It excludes environment files and credential
contents. Review any additional build output before sharing it.

## Later FRP / GitHub webhook setup

Tunnel to `127.0.0.1:8080` (or the chosen Jenkins port); update Jenkins's
public URL under **Manage Jenkins → System** after the tunnel works. The
GitHub webhook receiver path is `/github-webhook/`, with its trailing slash.
No FRP configuration is changed by this installer.

Local snapshot mode builds the local checkout even when a webhook triggers it.
For automatic builds of GitHub `main`, push the workflow changes, switch the
job to **Pipeline script from SCM**, set repository
`https://github.com/Trance-0/Notechondria.git`, branch `*/main`, script path
`Jenkinsfile`, and leave `LOCAL_SOURCE_DIR` empty. The deployment env stays on
this Ubuntu host. The managed installer restores local mode when rerun.

## Current host and reference environment (2026-10-30)

There are two controllers: the Docker controller at `http://127.0.0.1:8081`
(with agent `local-docker`, SCM `main`) and the systemd controller at
`http://127.0.0.1:8080`. Their credentials and build histories are separate.
The systemd controller can test an uncommitted local snapshot; the Docker
SCM job sees fixes only after the owner pushes them.

`local.env` at the checkout root is the private reference used for local
testing. It is ignored by Git and mode 0600. Its Casdoor and GitHub sync
settings come from `prod.env`; PostgreSQL credentials preserve the existing
local cluster. `DATABASE_URL` is empty and the backend Compose service
explicitly overrides it, so production database URLs cannot redirect local
migrations. Storage uses the existing local static/media volumes; production
R2 is deliberately not selected because startup clears collected static files.
This supplies the same application features using local storage instead of R2.
Do not copy the production database URL or R2 bucket into a local test env.

The Docker agent's private source is
`/var/lib/jenkins/secrets/notechondria-deploy.env` **inside the agent**, not
the same-looking path on the host. The pipeline's `DEPLOY_ENV_SOURCE`
parameter can point to another private file accessible by its selected agent.
Backend Compose forwards the full env file, including Casdoor and GitHub
sync; `ENV_FILE_PATH` points Compose to that file and is set by the scripts.

Local snapshot pipeline setup uses Jenkins Groovy sandbox mode. The managed
installer selects a fresh `/var/lib/jenkins/notechondria-workspace` for this
controller. An old
installer used an unsandboxed definition and failed before any stage with
`UnapprovedUsageException`; rerun the corrected installer to update it.
If an old workspace contains root-owned files, choose a fresh writable custom
workspace in the node agent configuration rather than removing unrelated files.

The Jenkins Build resources stage creates the `notechondria-local` Docker
Buildx container builder automatically, after checking available RAM. Its settings are
`memory=8g`, `cpu-period=100000`, `cpu-quota=400000`, `default-load=true`,
and `--buildkitd-flags '--oci-max-parallelism=1'`; export `BUILDX_BUILDER`
to that builder's name. Check available RAM first. The backend test container
is capped at 1 GiB; build commands have explicit timeouts. If a build fails
or stays silent for five minutes, inspect logs before retrying.

To run the same ordered gates outside Jenkins:

```bash
BUILDX_BUILDER=notechondria-local timeout 120m \
  bash deployment/jenkins/scripts/deploy_full_stack.sh "$PWD/local.env"
```

This helper runs backend tests, the three frontend smoke tests and shared
local-folder tests, PostgreSQL backup, backend deployment, sequential app
builds, gateway deployment, and HTTP verification. Web builds include local
CanvasKit resources. Persistent data volumes are retained.

Known optional credential gaps: `OPENAI_API_KEY` and SMTP server/user/password
are empty in the tested reference; AI requests and email delivery require
those credentials. Casdoor login also requires the identity provider to allow
the local app callback origins; the presence of its client credentials alone
does not verify that allowlist. GitHub App installation authorization remains
a per-user step. Never paste credential values into build logs.

The previous Docker build #10 failed because `backend/Dockerfile` omitted the
shared API contract JSON fixtures. The Docker image now includes them. The
contract test explicitly selects its unconfigured Casdoor fixture state so
real local SSO credentials do not change that expected response.

The two controllers originally had different generated deployment passwords.
Copy the same verified `local.env` to each controller/agent env source before
building against the shared local cluster; a successful backup using a local
PostgreSQL socket does not prove that the app password is correct over TCP.

## Verified result, 2026-10-30

System Jenkins build [#6](http://127.0.0.1:8080/job/notechondria/6/) succeeded:
281 backend tests, all three frontend smoke suites, 358 shared local-folder
tests, database backup, and the full deployment. All seven app containers
are healthy. All three compiled bundles report 0.1.203 and target the local
API. Casdoor configuration/discovery and GitHub sync PEM parsing passed.
Logs are retained at `logs/jenkins-build-6.log`; backups live outside the
workspace in `/var/lib/jenkins/backups/notechondria/`.

Browser sign-in/callbacks and user-authorized GitHub pushes remain untested.
The Docker controller's separate admin password/token was unavailable; its
SCM pipeline definition was not edited live. It will read the committed
Jenkinsfile after the owner pushes these changes. The system controller's
pipeline and boot configuration already contain the local fixes.
