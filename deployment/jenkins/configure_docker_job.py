"""Install the local pipeline on an existing Docker Jenkins controller.

Run on the host with JENKINS_PASSWORD set; credentials are never printed.
A sanitized committed source snapshot is staged on the Docker agent. Rerun
this helper after local edits, then use Build with Parameters in Jenkins.
"""
from __future__ import annotations

import argparse
import base64
import http.cookiejar
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:8081/')
    parser.add_argument('--user', default='admin')
    parser.add_argument('--agent', default='jenkins-local-docker')
    parser.add_argument('--source-dir', required=True,
                        help='New snapshot path under the agent host bind mount, outside its build workspace')
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    password = os.environ['JENKINS_PASSWORD']
    auth = 'Basic ' + base64.b64encode(f'{args.user}:{password}'.encode()).decode()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    crumb = {}

    def request(path, data=None, content_type=None):
        headers = {'Authorization': auth}
        if data is not None:
            headers.update(crumb)
        if content_type:
            headers['Content-Type'] = content_type
        with opener.open(urllib.request.Request(args.url.rstrip('/') + '/' + path,
                         data=data, headers=headers), timeout=30) as response:
            return response.read()

    identity = json.loads(request('whoAmI/api/json'))
    if not identity.get('authenticated'):
        raise SystemExit('Job unchanged: Jenkins.Configure/auth — supplied account is not authenticated')
    c = json.loads(request('crumbIssuer/api/json'))
    crumb[c['crumbRequestField']] = c['crumb']
    original = request('job/notechondria/config.xml')
    backup = repo / 'logs/jenkins-docker-job-before.xml'
    backup.parent.mkdir(exist_ok=True)
    if not backup.exists():
        backup.write_bytes(original)
        backup.chmod(0o600)
    with tempfile.TemporaryDirectory(prefix='notechondria-source-') as tmp:
        subprocess.run(['python3', str(repo / 'deployment/jenkins/snapshot_source.py'),
                        str(repo), tmp], check=True, timeout=60)
        subprocess.run(['git', 'init', '-q', tmp], check=True, timeout=30)
        subprocess.run(['git', '-C', tmp, 'add', '.'], check=True, timeout=30)
        subprocess.run(['git', '-C', tmp, '-c', 'user.name=Local Jenkins snapshot',
                        '-c', 'user.email=jenkins@localhost', 'commit', '-qm',
                        'Snapshot for local Jenkins verification'], check=True, timeout=30)
        # docker cp avoids shell interpolation of host or container paths.
        subprocess.run(['docker', 'exec', args.agent, 'mkdir', '-p', args.source_dir,
                        '/usr/local/lib/notechondria-jenkins'], check=True, timeout=30)
        subprocess.run(['docker', 'cp', tmp + '/.', f'{args.agent}:{args.source_dir}'],
                       check=True, timeout=60)
    agent_uid = subprocess.check_output(['docker', 'exec', args.agent, 'id', '-u'], text=True).strip()
    agent_gid = subprocess.check_output(['docker', 'exec', args.agent, 'id', '-g'], text=True).strip()
    subprocess.run(['docker', 'exec', args.agent, 'chown', '-R',
                    f'{agent_uid}:{agent_gid}', args.source_dir], check=True, timeout=60)
    builder = Path.home() / '.docker/buildx/instances/notechondria-local'
    if builder.exists():
        agent_home = subprocess.check_output(
            ['docker', 'exec', args.agent, 'printenv', 'HOME'], text=True).strip()
        target = agent_home + '/.docker/buildx/instances'
        subprocess.run(['docker', 'exec', args.agent, 'mkdir', '-p', target], check=True, timeout=30)
        subprocess.run(['docker', 'cp', str(builder), f'{args.agent}:{target}/notechondria-local'],
                       check=True, timeout=30)
    subprocess.run(['docker', 'cp', str(repo / 'deployment/jenkins/snapshot_source.py'),
                    f'{args.agent}:/usr/local/lib/notechondria-jenkins/snapshot_source.py'],
                   check=True, timeout=30)
    root = ET.fromstring(original)
    old_definition = root.find('definition')
    root.remove(old_definition)
    definition = ET.SubElement(root, 'definition',
                              {'class': 'org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition'})
    script = (repo / 'Jenkinsfile').read_text().replace('agent any', "agent { label 'local-docker' }", 1)
    script = script.replace("string(name: 'LOCAL_SOURCE_DIR', defaultValue: ''",
                            "string(name: 'LOCAL_SOURCE_DIR', defaultValue: " + json.dumps(args.source_dir))
    script = script.replace('checkout scm',
                            "git branch: 'main', url: 'https://github.com/Trance-0/Notechondria.git'")
    ET.SubElement(definition, 'script').text = script
    ET.SubElement(definition, 'sandbox').text = 'true'
    for param in root.findall('.//hudson.model.StringParameterDefinition'):
        if param.findtext('name') == 'LOCAL_SOURCE_DIR':
            default = param.find('defaultValue')
            if default is None:
                default = ET.SubElement(param, 'defaultValue')
            default.text = args.source_dir
    root.find('description').text = (
        'Local full-stack deployment on local-docker. Refresh source with '
        'configure_docker_job.py after edits. Empty LOCAL_SOURCE_DIR checks out GitHub main.')
    request('job/notechondria/config.xml', ET.tostring(root), 'application/xml')
    print('Job updated: Jenkins.Configure/docker — sandboxed pipeline and private agent env source configured')
    if args.build:
        data = urllib.parse.urlencode({'LOCAL_SOURCE_DIR': args.source_dir,
            'DEPLOY_ENV_SOURCE': '/var/lib/jenkins/secrets/notechondria-deploy.env'}).encode()
        request('job/notechondria/buildWithParameters', data, 'application/x-www-form-urlencoded')
        print('Build queued: Jenkins.Configure/docker — full-stack gates run on local-docker')


if __name__ == '__main__':
    main()
