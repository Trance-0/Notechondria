"""Configure an existing Docker Jenkins job to build GitHub main via webhook.

Run on the host with JENKINS_PASSWORD set; credentials are never printed.
Deployment secrets remain in the existing private env file on local-docker.
"""
from __future__ import annotations

import argparse
import base64
import http.cookiejar
import json
import os
from pathlib import Path
import urllib.request
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:8081/')
    parser.add_argument('--user', default='admin')
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
    backup = repo / 'logs/jenkins-docker-job-before-scm.xml'
    backup.parent.mkdir(exist_ok=True)
    if not backup.exists():
        backup.write_bytes(original)
        backup.chmod(0o600)
    root = ET.fromstring(original)
    root.remove(root.find('definition'))
    definition = ET.SubElement(root, 'definition',
                              {'class': 'org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition'})
    scm = ET.SubElement(definition, 'scm', {'class': 'hudson.plugins.git.GitSCM'})
    ET.SubElement(scm, 'configVersion').text = '2'
    remotes = ET.SubElement(scm, 'userRemoteConfigs')
    remote = ET.SubElement(remotes, 'hudson.plugins.git.UserRemoteConfig')
    ET.SubElement(remote, 'url').text = 'https://github.com/Trance-0/Notechondria.git'
    branches = ET.SubElement(scm, 'branches')
    ET.SubElement(ET.SubElement(branches, 'hudson.plugins.git.BranchSpec'), 'name').text = '*/main'
    ET.SubElement(scm, 'doGenerateSubmoduleConfigurations').text = 'false'
    ET.SubElement(scm, 'submoduleCfg', {'class': 'empty-list'})
    ET.SubElement(scm, 'extensions')
    ET.SubElement(definition, 'scriptPath').text = 'Jenkinsfile'
    ET.SubElement(definition, 'lightweight').text = 'false'
    properties = root.find('properties')
    if properties is None:
        properties = ET.SubElement(root, 'properties')
    for params in properties.findall('hudson.model.ParametersDefinitionProperty'):
        properties.remove(params)
    triggers_prop = properties.find('org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty')
    if triggers_prop is None:
        triggers_prop = ET.SubElement(properties, 'org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty')
    triggers = triggers_prop.find('triggers')
    if triggers is None:
        triggers = ET.SubElement(triggers_prop, 'triggers')
    if triggers.find('com.cloudbees.jenkins.GitHubPushTrigger') is None:
        ET.SubElement(ET.SubElement(triggers, 'com.cloudbees.jenkins.GitHubPushTrigger'), 'spec')
    tracker = root.find('actions/org.jenkinsci.plugins.pipeline.modeldefinition.actions.DeclarativeJobPropertyTrackerAction/parameters')
    if tracker is not None:
        for item in list(tracker):
            if item.text == 'LOCAL_SOURCE_DIR':
                tracker.remove(item)
    root.find('description').text = (
        'GitHub main via webhook → tests → database backup → full-stack deployment. '
        'Private deployment env remains on local-docker.')
    request('job/notechondria/config.xml', ET.tostring(root), 'application/xml')
    installed = ET.fromstring(request('job/notechondria/config.xml'))
    assert installed.find('definition').get('class').endswith('CpsScmFlowDefinition')
    assert installed.findtext('definition/scm/branches/hudson.plugins.git.BranchSpec/name') == '*/main'
    print('Job verified: Jenkins.Configure/scm — GitHub main, Jenkinsfile, and push trigger configured')


if __name__ == '__main__':
    main()
