"""Back up a Cloudflare R2 bucket to a timestamped tar archive.

Click-run defaults:
- reads R2 credentials from the repo-root `.env`
- writes to `scripts/r2_backup/<YYYYmmdd-HHMMSS>.tar`

Optional operator edits:
- set USER_SELECTED_BACKUP_DIR to another directory
- set BACKUP_FILENAME to a fixed filename

Uses Python stdlib only. No boto3 or AWS CLI is required.
"""

from __future__ import annotations

import hashlib
import hmac
import io
import json
import tarfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import quote


ENV_FILE = Path(__file__).resolve().parents[1] / ".env"
USER_SELECTED_BACKUP_DIR: Optional[str] = None
BACKUP_FILENAME: Optional[str] = None
R2_REGION = "auto"
R2_SERVICE = "s3"


def _fail(process: str, cause: str) -> None:
    raise SystemExit(
        f"Cloudflare storage backup not created: "
        f"Ops.Backup.CloudflareR2/{process} - {cause}."
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


def _backup_path() -> Path:
    backup_dir = (
        Path(USER_SELECTED_BACKUP_DIR)
        if USER_SELECTED_BACKUP_DIR
        else Path(__file__).resolve().parent / "r2_backup"
    )
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    filename = BACKUP_FILENAME or f"{stamp}.tar"
    if not filename.endswith(".tar"):
        filename = f"{filename}.tar"
    backup_dir.mkdir(parents=True, exist_ok=True)
    return backup_dir / filename


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


def _list_objects(config: Dict[str, str]) -> List[Dict[str, str]]:
    objects: List[Dict[str, str]] = []
    token: Optional[str] = None
    while True:
        query = {"list-type": "2"}
        if token:
            query["continuation-token"] = token
        body, _headers = _request(config, "GET", query=query)
        root = ET.fromstring(body)
        for item in root.findall(".//{*}Contents"):
            objects.append(
                {
                    "key": _xml_text(item, "Key"),
                    "size": _xml_text(item, "Size"),
                    "etag": _xml_text(item, "ETag").strip('"'),
                    "last_modified": _xml_text(item, "LastModified"),
                }
            )
        is_truncated = _xml_text(root, "IsTruncated").lower() == "true"
        token = _xml_text(root, "NextContinuationToken")
        if not is_truncated or not token:
            return objects


def _add_bytes(tar: tarfile.TarFile, name: str, data: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mtime = int(datetime.now(timezone.utc).timestamp())
    tar.addfile(info, fileobj=io.BytesIO(data))


def main() -> int:
    config = _r2_config(_load_env(ENV_FILE))
    output = _backup_path()
    temp_output = output.with_name(f"{output.name}.part")
    if temp_output.exists():
        temp_output.unlink()
    print(
        "Cloudflare storage backup started: Ops.Backup.CloudflareR2/list - "
        f"listing bucket {config['bucket']}."
    )
    objects = _list_objects(config)
    manifest_objects: List[Dict[str, str]] = []

    try:
        with tarfile.open(temp_output, "w") as archive:
            for index, item in enumerate(objects, start=1):
                key = item["key"]
                stored_path = f"objects/{index:08d}.bin"
                print(
                    "Cloudflare storage backup progress: "
                    f"Ops.Backup.CloudflareR2/download - {index}/{len(objects)} {key}."
                )
                data, headers = _request(config, "GET", key=key)
                _add_bytes(archive, stored_path, data)
                manifest_objects.append(
                    {
                        **item,
                        "stored_path": stored_path,
                        "content_type": headers.get("content-type", "application/octet-stream"),
                        "downloaded_size": str(len(data)),
                    }
                )

            manifest = {
                "format": "notechondria-cloudflare-r2-backup-v1",
                "created_at": datetime.now(timezone.utc).isoformat(),
                "bucket": config["bucket"],
                "object_count": len(manifest_objects),
                "objects": manifest_objects,
            }
            _add_bytes(
                archive,
                "manifest.json",
                json.dumps(manifest, indent=2, sort_keys=True).encode("utf-8"),
            )
        temp_output.replace(output)
    except BaseException:
        if temp_output.exists():
            temp_output.unlink()
        raise

    print(
        "Cloudflare storage backup created: Ops.Backup.CloudflareR2/tar_write - "
        f"{output} ({output.stat().st_size} bytes, {len(objects)} object(s))."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Cloudflare storage backup aborted: Ops.Backup.CloudflareR2/keyboard_interrupt - user interrupted the run.")
        raise SystemExit(130)
