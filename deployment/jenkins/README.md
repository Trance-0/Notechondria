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
failure. Copy that block into chat. To collect a fresh report:

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
