"""Verify authentication and job provisioning without displaying the admin password."""
import base64
import json
from pathlib import Path
import sys
import urllib.request

port = int(sys.argv[1])
password = Path("/var/lib/jenkins/secrets/notechondria-admin-password").read_text().strip()
auth = base64.b64encode(f"admin:{password}".encode()).decode()
request = urllib.request.Request(
    f"http://127.0.0.1:{port}/job/notechondria/api/json?tree=name,buildable",
    headers={"Authorization": f"Basic {auth}"},
)
with urllib.request.urlopen(request, timeout=20) as response:
    job = json.load(response)
if job.get("name") != "notechondria" or not job.get("buildable"):
    raise SystemExit("Install verification failed: Jenkins.Install/job — pipeline is absent or disabled")
print("Jenkins.Install/verify — authenticated API and buildable Notechondria job verified")
