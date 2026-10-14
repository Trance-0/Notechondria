"""Remove credentials and the setup-wizard password from pasteable diagnostics."""
import re
import sys

for line in sys.stdin:
    if re.search(r"password|secret|token|authorization|credential", line, re.I):
        print("[credential-related log line omitted]")
    else:
        line = re.sub(r"\b[0-9a-f]{32,}\b", "[redacted identifier]", line)
        line = re.sub(r"(https?://)[^/\s]+:[^@\s]+@", r"\1[redacted]@", line)
        sys.stdout.write(line)
