"""Configure systemd and a one-time authenticated Jenkins bootstrap."""
import base64
import json
import os
from pathlib import Path
import pwd
import secrets
import sys

repo, user, group, port = sys.argv[1:]
home = Path("/var/lib/jenkins")
owner = pwd.getpwnam(user)

# Jenkins creates its own master key here during boot. Creating only the
# credential files as the service user leaves their parent root-owned.
for directory, mode in ((home / "secrets", 0o700), (home / "init.groovy.d", 0o700)):
    directory.mkdir(parents=True, exist_ok=True)
    os.chown(directory, owner.pw_uid, owner.pw_gid)
    directory.chmod(mode)


def write(path, text, mode=0o600):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)
    os.chown(path, owner.pw_uid, owner.pw_gid)


write("/etc/systemd/system/jenkins.service.d/notechondria.conf", f"""[Service]
User={user}
Group={group}
Environment="JENKINS_HOME=/var/lib/jenkins"
Environment="JENKINS_PORT={port}"
Environment="JENKINS_LISTEN_ADDRESS=127.0.0.1"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false -Xmx2g"
TimeoutStartSec=600
""", 0o644)
password_path = home / "secrets/notechondria-admin-password"
if not password_path.exists():
    write(password_path, secrets.token_urlsafe(32) + "\n")
env_path = home / "secrets/notechondria-deploy.env"
if not env_path.exists():
    write(env_path, f"""DJANGO_SECRET_KEY={secrets.token_hex(32)}
DJANGO_DEBUG=False
DJANGO_LOG_LEVEL=INFO
DJANGO_LOG_FILE_NAME=notechondria
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
DJANGO_ALLOWED_HOSTS_COMPOSE='localhost 127.0.0.1'
DJANGO_CSRF_TRUSTED_ORIGINS=http://localhost:9060,http://127.0.0.1:9060
DJANGO_SUPERUSER_USERNAME=admin
DJANGO_SUPERUSER_EMAIL=admin@localhost
DJANGO_SUPERUSER_PASSWORD={secrets.token_urlsafe(24)}
POSTGRE_USERNAME=notechondria
POSTGRE_PASSWORD={secrets.token_hex(24)}
POSTGRE_DB=notechondria
POSTGRE_HOST=db
POSTGRE_PORT=5432
APP_HOST_PORT=9080
BACKEND_HOST_PORT=9090
DB_HOST_PORT=9032
FRONTEND_HOST_PORT=9060
ROOT_HTTP_PORT=9060
FRONTEND_API_BASE_URL=http://localhost:9060/api/v1
FRONTEND_BACKEND_ORIGIN=http://backend_nginx
FRONTEND_VERIFY_URL=http://localhost:9060/portal/#/verify
OPENAI_API_KEY=
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_USE_TLS=True
SMTP_USE_SSL=False
SMTP_FROM_EMAIL=no-reply@localhost
SMTP_EMAIL_VERIFICATION_TTL_HOURS=24
DJANGO_PRODUCTION_STATIC_ROOT=/home/staticfiles/
DJANGO_PRODUCTION_MEDIA_ROOT=/home/mediafiles/
DB_AUTO_REINIT_IF_MISMATCH=False
""")
# JSON string syntax is also valid for the Groovy strings used here.
pipeline_text = (Path(repo) / "Jenkinsfile").read_text().replace(
    "defaultValue: ''", "defaultValue: " + json.dumps(repo), 1
)
pipeline_encoded = base64.b64encode(pipeline_text.encode()).decode()
repo_literal = json.dumps(repo)
write(home / "init.groovy.d/10-notechondria.groovy", f"""import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.model.ParametersDefinitionProperty
import hudson.model.StringParameterDefinition
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition

def j = Jenkins.get()
def marker = new File(j.rootDir, '.notechondria-bootstrap-complete')
if (!marker.exists()) {{
    if (!(j.securityRealm instanceof HudsonPrivateSecurityRealm)) {{
        def realm = new HudsonPrivateSecurityRealm(false)
        realm.createAccount('admin', new File(j.rootDir, 'secrets/notechondria-admin-password').text.trim())
        j.setSecurityRealm(realm)
        def auth = new FullControlOnceLoggedInAuthorizationStrategy()
        auth.setAllowAnonymousRead(false)
        j.setAuthorizationStrategy(auth)
    }}
    j.setNumExecutors(1)
    j.setSlaveAgentPort(-1)
    JenkinsLocationConfiguration.get().setUrl('http://127.0.0.1:{port}/')
    j.save()
}}
def job = j.getItem('notechondria')
if (job == null) {{ job = j.createProject(WorkflowJob, 'notechondria') }}
job.setDefinition(new CpsFlowDefinition(new String('{pipeline_encoded}'.decodeBase64(), 'UTF-8'), false))
job.addProperty(new ParametersDefinitionProperty(
    new StringParameterDefinition('LOCAL_SOURCE_DIR', {repo_literal}, 'Trusted local checkout copied at build start.')))
job.setDescription('Local Ubuntu Docker deployment. Sequential tests gate deployment; database backups are retained outside the workspace.')
job.save()
marker.text = 'configured\\n'
println('Jenkins.Install/bootstrap — authenticated Notechondria job configured')
""")
