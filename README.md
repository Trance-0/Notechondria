# Notechondria

This is the last app I developed in Django full-stack, this is the first, and the last complete project that I will commit to and maintain for the rest of my life.

[![wakatime](https://wakatime.com/badge/user/53e0bfc9-ae89-4cb3-99fe-c6cbc6359857/project/018d7a17-526b-478b-9482-104ce6cd377a.svg)](https://wakatime.com/badge/user/53e0bfc9-ae89-4cb3-99fe-c6cbc6359857/project/018d7a17-526b-478b-9482-104ce6cd377a)

May your note be your power for success.

This page is updated on 2023/12/4

Notechondria names from the Note and Mitochondria, we wish the note could be the power that fosters personal accomplishments rather than text or drawing on iPad or other media. We wish to connect all the data to create an easily accessible database for each individual in the age of information.

Some of the key features of the app include:

* Use generative AI to connect notes with auto-tagging.
* Use generative AI to parse the note to others.
* Share the note seamlessly across devices and media, including images, datasets, latex, markdown, etc.
* Card-like note truncation and auto-generate the note for the day based on user output

We will not share or sell any data with others because the developer is the app's main user.

We will not use your knowledge to feed the AI, we use open API and ensure that your original ideas and thoughts will not be used for training.

## Repository layout

* `backend/` - Django backend services and infrastructure.
* `frontend/` - Flutter client application.
* `docs/` - Product documentation, MVP scope, and planning references.
* `course_template/` - Canonical git course template for import/export and validation.


## Operations and integration docs

* API spec and example requests: `docs/api/backend_api_spec.md`
* Deployment instructions: `docs/deployment/deploy.md`
* GitHub App integration guide: `docs/integrations/github_app_integration.md`
* CI/CD pipeline definition: `Jenkinsfile`
* Environment template: `sample.env`
* Test deployment env example: `sample.test.env`
* Jenkins environment injection guide: `docs/deployment/deploy.md`
* Build-from-scratch prompt report: `CODEX.md`
* LLM delivery checklist: `LLM_CHECK.md`

## Jenkins Deployment

This repository is set up for a Jenkins Pipeline job that:

* checks out the `codex` branch,
* injects deployment variables before the build,
* renders `.env.deploy` in the workspace,
* runs backup/test/deploy through Docker only.

### Required plugins

* Git plugin: [plugins.jenkins.io/git](https://plugins.jenkins.io/git/)
* GitHub plugin: [plugins.jenkins.io/github](https://plugins.jenkins.io/github/)
* Docker Pipeline plugin: [plugins.jenkins.io/docker-workflow](https://plugins.jenkins.io/docker-workflow/)
* Environment Injector plugin: [plugins.jenkins.io/envinject](https://plugins.jenkins.io/envinject/)

### Job setup

* Use a `Pipeline script from SCM` job.
* Set the repository to `https://github.com/Trance-0/Notechondria.git`.
* Set the branch to `codex`.
* If the repository is public, leave SCM credentials empty. The credentials shown in Jenkins logs come from the job SCM configuration, not from the Jenkinsfile.
* Enable `GitHub hook trigger for GITScm polling` if you want GitHub push webhooks to trigger the build.

### Environment Injector setup

* Enable `Prepare an environment for the run`.
* Check `Keep Jenkins Environment Variables`.
* Check `Keep Jenkins Build Variables`.
* Put deployment variables in `Properties Content`.
* Keep `DJANGO_ALLOWED_HOSTS` comma-separated.
* Keep `DJANGO_ALLOWED_HOSTS_COMPOSE` space-separated.

Example:

```properties
DJANGO_SECRET_KEY=replace-with-real-secret
DJANGO_DEBUG=False
DJANGO_PORT=8000
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,test.notechondria.local
DJANGO_ALLOWED_HOSTS_COMPOSE=localhost 127.0.0.1 test.notechondria.local
DJANGO_LOG_LEVEL=INFO
DJANGO_LOG_FILE_NAME=notechondria-test
POSTGRE_USERNAME=postgres
POSTGRE_PASSWORD=postgres
POSTGRE_HOST=db
POSTGRE_PORT=5432
POSTGRE_DB=postgres
NGINX_PORT=8080
PRODUCTION_STATIC_ROOT=/home/staticfiles/
PRODUCTION_MEDIA_ROOT=/home/mediafiles/
OPENAI_API_KEY=
GITHUB_APP_ID=
GITHUB_APP_CLIENT_ID=
GITHUB_APP_CLIENT_SECRET=
GITHUB_APP_PRIVATE_KEY_PATH=
GITHUB_APP_WEBHOOK_SECRET=
```

See [`docs/deployment/deploy.md`](D:\Documents\Github\Notechondria\docs\deployment\deploy.md) for the fuller deployment flow.
