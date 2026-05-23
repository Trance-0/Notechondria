"""Restore a Cloudflare R2 bucket from a tar archive.

Click-run defaults:
- reads target R2 credentials from the repo-root `.env`
- restores the newest `scripts/r2_backup/*.tar`
- overwrites matching object keys, but does not delete extra remote keys

Optional operator edits:
- set USER_SELECTED_BACKUP_DIR to another directory
- set RESTORE_FILE to an exact tar path
- set DELETE_REMOTE_OBJECTS_NOT_IN_BACKUP to True for exact replacement
- set REQUIRE_CONFIRMATION to False only for trusted automation

Uses Python stdlib only. No boto3 or AWS CLI is required.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import tarfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
from urllib.parse import quote


ENV_FILE = Path(__file__).resolve().parents[1] / ".env"
USER_SELECTED_BACKUP_DIR: Optional[str] = None
RESTORE_FILE: Optional[str] = None
REQUIRE_CONFIRMATION = True
DELETE_REMOTE_OBJECTS_NOT_IN_BACKUP = False
R2_REGION = "auto"
R2_SERVICE = "s3"


def _fail(process: str, cause: str) -> None:
    raise SystemExit(
        f"Cloudflare storage restore not completed: "
        f"Ops.Restore.CloudflareR2/{process} - {cause}."
    )


def _load_env(path: Path) -> Dict[str, str]:
    if not path.exists():
        _fail("env_load", f"root .env file not found at {path}")
    values: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        values[key] = value
    return values


def _r2_config(env: Dict[str, str]) -> Dict[str, str]:
    names = [
        "CLOUDFLARE_R2_BUCKET_NAME",
        "CLOUDFLARE_R2_ACCOUNT_ID",
        "CLOUDFLARE_R2_ACCESS_KEY_ID",
        "CLOUDFLARE_R2_SECRET_ACCESS_KEY",
    ]
    missing = [name for name in names if not env.get(name, "").strip()]
    if missing:
        _fail("env_parse", f"missing required R2 variable(s): {', '.join(missing)}")
    return {
        "bucket": env["CLOUDFLARE_R2_BUCKET_NAME"],
        "account_id": env["CLOUDFLARE_R2_ACCOUNT_ID"],
        "access_key": env["CLOUDFLARE_R2_ACCESS_KEY_ID"],
        "secret_key": env["CLOUDFLARE_R2_SECRET_ACCESS_KEY"],
        "host": f"{env['CLOUDFLARE_R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
    }


def _restore_path() -> Path:
    if RESTORE_FILE:
        path = Path(RESTORE_FILE)
        if not path.exists():
            _fail("select_backup", f"restore file not found at {path}")
        return path

    backup_dir = (
        Path(USER_SELECTED_BACKUP_DIR)
        if USER_SELECTED_BACKUP_DIR
        else Path(__file__).resolve().parent / "r2_backup"
    )
    if not backup_dir.exists():
        _fail("select_backup", f"backup directory not found at {backup_dir}")
    candidates = sorted(
        backup_dir.glob("*.tar"),
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        _fail("select_backup", f"no .tar backup files found in {backup_dir}")
    return candidates[0]


def _signing_key(secret_key: str, date_stamp: str) -> bytes:
    key = ("AWS4" + secret_key).encode("utf-8")
    for value in (date_stamp, R2_REGION, R2_SERVICE, "aws4_request"):
        key = hmac.new(key, value.encode("utf-8"), hashlib.sha256).digest()
    return key


def _canonical_query(params: Dict[str, str]) -> str:
    pairs = []
    for key in sorted(params):
        pairs.append(f"{quote(key, safe='-_.~')}={quote(params[key], safe='-_.~')}")
    return "&".join(pairs)


def _request(
    config: Dict[str, str],
    method: str,
    key: str = "",
    query: Optional[Dict[str, str]] = None,
    body: Optional[bytes] = None,
    content_type: Optional[str] = None,
) -> Tuple[bytes, Dict[str, str]]:
    query = query or {}
    body = body or b""
    now = datetime.now(timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    path = f"/{config['bucket']}"
    if key:
        path += "/" + key
    canonical_uri = quote(path, safe="/-_.~")
    canonical_query = _canonical_query(query)
    payload_hash = hashlib.sha256(body).hexdigest()

    headers = {
        "host": config["host"],
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": amz_date,
    }
    if content_type:
        headers["content-type"] = content_type
    signed_header_names = sorted(headers)
    canonical_headers = "".join(
        f"{name}:{headers[name]}\n" for name in signed_header_names
    )
    signed_headers = ";".join(signed_header_names)
    canonical_request = "\n".join(
        [
            method,
            canonical_uri,
            canonical_query,
            canonical_headers,
            signed_headers,
            payload_hash,
        ]
    )
    credential_scope = f"{date_stamp}/{R2_REGION}/{R2_SERVICE}/aws4_request"
    string_to_sign = "\n".join(
        [
            "AWS4-HMAC-SHA256",
            amz_date,
            credential_scope,
            hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
        ]
    )
    signature = hmac.new(
        _signing_key(config["secret_key"], date_stamp),
        string_to_sign.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    headers["authorization"] = (
        "AWS4-HMAC-SHA256 "
        f"Credential={config['access_key']}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )

    url = f"https://{config['host']}{canonical_uri}"
    if canonical_query:
        url = f"{url}?{canonical_query}"
    request = urllib.request.Request(
        url,
        data=body if method in {"PUT", "POST"} else None,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return response.read(), {k.lower(): v for k, v in response.headers.items()}
    except urllib.error.HTTPError as error:
        detail = error.read(512).decode("utf-8", errors="replace").strip()
        _fail("http_request", f"R2 returned HTTP {error.code}: {detail}")
    except urllib.error.URLError as error:
        _fail("http_request", str(error.reason))
    raise AssertionError("unreachable")


def _xml_text(element: ET.Element, local_name: str) -> str:
    for child in element:
        if child.tag.endswith(local_name):
            return child.text or ""
    return ""


def _list_object_keys(config: Dict[str, str]) -> Set[str]:
    keys: Set[str] = set()
    token: Optional[str] = None
    while True:
        query = {"list-type": "2"}
        if token:
            query["continuation-token"] = token
        body, _headers = _request(config, "GET", query=query)
        root = ET.fromstring(body)
        for item in root.findall(".//{*}Contents"):
            keys.add(_xml_text(item, "Key"))
        is_truncated = _xml_text(root, "IsTruncated").lower() == "true"
        token = _xml_text(root, "NextContinuationToken")
        if not is_truncated or not token:
            return keys


def _read_manifest(archive: tarfile.TarFile) -> Dict[str, object]:
    try:
        manifest_file = archive.extractfile("manifest.json")
    except KeyError:
        _fail("manifest_read", "manifest.json missing from R2 backup tar")
    if manifest_file is None:
        _fail("manifest_read", "manifest.json could not be read")
    manifest = json.loads(manifest_file.read().decode("utf-8"))
    if manifest.get("format") != "notechondria-cloudflare-r2-backup-v1":
        _fail("manifest_read", "backup format is not notechondria-cloudflare-r2-backup-v1")
    return manifest


def _confirm(path: Path, count: int, exact_replace: bool) -> None:
    if not REQUIRE_CONFIRMATION:
        return
    mode = "overwrite and delete extras" if exact_replace else "overwrite only"
    print(
        "Cloudflare storage restore confirmation required: "
        "Ops.Restore.CloudflareR2/confirm - "
        f"{count} object(s) will be restored from {path} ({mode})."
    )
    typed = input("Type RESTORE_R2 to continue: ").strip()
    if typed != "RESTORE_R2":
        _fail("confirm", "confirmation phrase did not match")


def main() -> int:
    config = _r2_config(_load_env(ENV_FILE))
    source = _restore_path()
    with tarfile.open(source, "r") as archive:
        manifest = _read_manifest(archive)
        objects = manifest.get("objects")
        if not isinstance(objects, list):
            _fail("manifest_read", "manifest objects field is not a list")
        _confirm(source, len(objects), DELETE_REMOTE_OBJECTS_NOT_IN_BACKUP)

        restored_keys: Set[str] = set()
        for index, item in enumerate(objects, start=1):
            if not isinstance(item, dict):
                _fail("manifest_read", f"object manifest row {index} is not a map")
            key = str(item.get("key", ""))
            stored_path = str(item.get("stored_path", ""))
            if not key or not stored_path.startswith("objects/"):
                _fail("manifest_read", f"object manifest row {index} is incomplete")
            member_file = archive.extractfile(stored_path)
            if member_file is None:
                _fail("tar_read", f"tar member missing for key {key}")
            data = member_file.read()
            content_type = str(item.get("content_type") or "application/octet-stream")
            print(
                "Cloudflare storage restore progress: "
                f"Ops.Restore.CloudflareR2/upload - {index}/{len(objects)} {key}."
            )
            _request(config, "PUT", key=key, body=data, content_type=content_type)
            restored_keys.add(key)

    if DELETE_REMOTE_OBJECTS_NOT_IN_BACKUP:
        existing = _list_object_keys(config)
        extras = sorted(existing - restored_keys)
        for index, key in enumerate(extras, start=1):
            print(
                "Cloudflare storage restore progress: "
                f"Ops.Restore.CloudflareR2/delete_extra - {index}/{len(extras)} {key}."
            )
            _request(config, "DELETE", key=key)

    print(
        "Cloudflare storage restore completed: "
        "Ops.Restore.CloudflareR2/upload - "
        f"{len(restored_keys)} object(s) restored into bucket {config['bucket']}."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Cloudflare storage restore aborted: Ops.Restore.CloudflareR2/keyboard_interrupt - user interrupted the run.")
        raise SystemExit(130)
