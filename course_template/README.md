# Course Template

This directory defines the canonical git-backed course template.

## Structure

```
course_template/
  course.yaml
  modules/
  assignments/
  assets/
```

## Usage

- `course.yaml` is the source of truth for metadata, modules, and assignments.
- Markdown files store content.
- YAML rubric files define grading/assessment.
- The validator expects `course.yaml` to use JSON-compatible YAML (valid JSON syntax).

Run the validator from the repository root:

```
python backend/scripts/validate_course_template.py course_template
```
