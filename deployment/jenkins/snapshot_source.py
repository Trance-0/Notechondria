"""Copy Git-visible local source into Jenkins without ignored credentials or Git metadata."""
import pathlib
import shutil
import subprocess
import sys

source, target = (pathlib.Path(arg).resolve() for arg in sys.argv[1:3])
if source == target or source in target.parents or target in source.parents:
    raise SystemExit("Snapshot refused: Jenkins.Source/copy — source and destination overlap")
target.mkdir(parents=True, exist_ok=True)
files = subprocess.check_output(
    ["git", "-C", str(source), "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
).decode().split("\0")
count = 0
for name in sorted(set(files)):
    if not name:
        continue
    path = pathlib.PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        raise SystemExit("Snapshot refused: Jenkins.Source/copy — invalid Git path")
    # Protect against accidentally tracked credentials as well as ignored ones.
    if name.endswith((".env", ".pem")) or any(p.startswith(".env") for p in path.parts):
        continue
    original = source / name
    if not original.is_file() or original.is_symlink():
        continue
    destination = target / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original, destination)
    count += 1
    if count % 200 == 0:
        print(f"Jenkins.Source/copy — copied {count} files", flush=True)
print(f"Jenkins.Source/copy — snapshot ready: {count} files", flush=True)
