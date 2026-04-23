#!/usr/bin/env python3
import argparse
import pathlib
import sys

import json

REQUIRED_COURSE_FIELDS = {"id", "title", "description", "owner", "visibility", "planning_horizon_days"}


def load_course_spec(path: pathlib.Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        raw = handle.read()

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(
            "course.yaml must be JSON-compatible YAML (valid JSON syntax) for validation."
        ) from exc


def validate_course_yaml(base_dir: pathlib.Path) -> list[str]:
    errors: list[str] = []
    course_path = base_dir / "course.yaml"
    if not course_path.exists():
        return ["course.yaml is missing"]

    try:
        data = load_course_spec(course_path)
    except ValueError as exc:
        return [str(exc)]
    course = data.get("course", {})
    missing = REQUIRED_COURSE_FIELDS - set(course.keys())
    if missing:
        errors.append(f"Missing required course fields: {', '.join(sorted(missing))}")

    for section_name in ("modules", "assignments", "assets"):
        if section_name not in data:
            errors.append(f"Missing required section: {section_name}")

    modules = data.get("modules", [])
    for module in modules:
        content_path = base_dir / module.get("content", "")
        if not content_path.exists():
            errors.append(f"Module content missing: {module.get('content')}")

    assignments = data.get("assignments", [])
    for assignment in assignments:
        content_path = base_dir / assignment.get("content", "")
        if not content_path.exists():
            errors.append(f"Assignment content missing: {assignment.get('content')}")
        rubric_path = base_dir / assignment.get("rubric", "")
        if not rubric_path.exists():
            errors.append(f"Assignment rubric missing: {assignment.get('rubric')}")

    for asset in data.get("assets", []):
        asset_path = base_dir / asset
        if not asset_path.exists():
            errors.append(f"Asset missing: {asset}")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the course template structure.")
    parser.add_argument("path", help="Path to course template root")
    args = parser.parse_args()

    base_dir = pathlib.Path(args.path)
    if not base_dir.exists():
        print(f"Path does not exist: {base_dir}", file=sys.stderr)
        return 1

    errors = validate_course_yaml(base_dir)
    if errors:
        print("Validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("Course template validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
