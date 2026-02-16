#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path


def extract_notes(changelog_path: Path, tag: str) -> str:
    if not changelog_path.exists():
        raise RuntimeError(f"Missing changelog: {changelog_path}")

    target_heading = f"## [{tag}]"
    lines = changelog_path.read_text(encoding="utf-8").splitlines()

    start = None
    for i, line in enumerate(lines):
        if line.strip() == target_heading:
            start = i + 1
            break

    if start is None:
        raise RuntimeError(f"No changelog heading found for {tag}")

    end = len(lines)
    for i in range(start, len(lines)):
        if lines[i].startswith("## ["):
            end = i
            break

    section = "\n".join(lines[start:end]).strip()
    if not section:
        section = "- Maintenance release."
    return section


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract release notes for a tag from CHANGELOG.md"
    )
    parser.add_argument("--tag", required=True, help="Tag name, e.g. v1.0.0")
    parser.add_argument("--changelog", default="CHANGELOG.md", help="Path to changelog")
    args = parser.parse_args()

    notes = extract_notes(Path(args.changelog), args.tag)
    print(notes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
