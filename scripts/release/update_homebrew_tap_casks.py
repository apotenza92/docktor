#!/usr/bin/env python3
"""Update DockActioner Homebrew casks in apotenza92/homebrew-tap.

Policy:
- Stable cask tracks latest stable tag (vX.Y.Z).
- Beta cask tracks whichever is newer between latest stable and latest prerelease.
  This keeps beta-channel users moving forward even when stable surpasses beta.
- Beta artifacts install side-by-side as DockActioner Beta.app.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


STABLE_TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
PRERELEASE_TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)-([0-9A-Za-z.-]+)$")


@dataclasses.dataclass(frozen=True)
class ParsedTag:
    major: int
    minor: int
    patch: int
    prerelease: str | None


@dataclasses.dataclass(frozen=True)
class Release:
    tag_name: str
    draft: bool
    prerelease_flag: bool
    parsed: ParsedTag


def parse_tag(tag: str) -> ParsedTag | None:
    stable = STABLE_TAG_RE.match(tag)
    if stable:
        return ParsedTag(
            int(stable.group(1)), int(stable.group(2)), int(stable.group(3)), None
        )

    prerelease = PRERELEASE_TAG_RE.match(tag)
    if prerelease:
        return ParsedTag(
            int(prerelease.group(1)),
            int(prerelease.group(2)),
            int(prerelease.group(3)),
            prerelease.group(4),
        )

    return None


def prerelease_key(prerelease: str) -> tuple[tuple[int, int | str], ...]:
    tokens: list[tuple[int, int | str]] = []
    for part in re.split(r"[.-]", prerelease):
        if part.isdigit():
            tokens.append((0, int(part)))
        else:
            tokens.append((1, part.lower()))
    return tuple(tokens)


def version_key(
    parsed: ParsedTag,
) -> tuple[int, int, int, int, tuple[tuple[int, int | str], ...]]:
    is_stable = 1 if parsed.prerelease is None else 0
    suffix = () if parsed.prerelease is None else prerelease_key(parsed.prerelease)
    return (parsed.major, parsed.minor, parsed.patch, is_stable, suffix)


def fetch_releases(repo: str) -> list[Release]:
    url = f"https://api.github.com/repos/{repo}/releases"
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "dock-actioner-homebrew-sync",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Failed to fetch releases from {repo}: {exc}") from exc

    output: list[Release] = []
    for item in payload:
        tag = item.get("tag_name", "")
        parsed = parse_tag(tag)
        if parsed is None:
            continue
        output.append(
            Release(
                tag_name=tag,
                draft=bool(item.get("draft", False)),
                prerelease_flag=bool(item.get("prerelease", False)),
                parsed=parsed,
            )
        )

    return [release for release in output if not release.draft]


def pick_latest(releases: list[Release]) -> Release | None:
    if not releases:
        return None
    return max(releases, key=lambda release: version_key(release.parsed))


def version_string(parsed: ParsedTag) -> str:
    base = f"{parsed.major}.{parsed.minor}.{parsed.patch}"
    if parsed.prerelease:
        return f"{base}-{parsed.prerelease}"
    return base


def render_stable_cask(repo: str, version: str) -> str:
    return f'''cask "dock-actioner" do
  version "{version}"
  sha256 :no_check

  on_arm do
    url "https://github.com/{repo}/releases/download/v#{{version}}/DockActioner-v#{{version}}-macos-arm64.zip"
  end

  on_intel do
    url "https://github.com/{repo}/releases/download/v#{{version}}/DockActioner-v#{{version}}-macos-x64.zip"
  end

  name "DockActioner"
  desc "Dock gesture actions for macOS"
  homepage "https://github.com/{repo}"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "DockActioner.app"

  zap trash: [
    "~/Library/Application Support/DockActioner",
    "~/Library/Caches/pzc.DockActioner",
    "~/Library/Preferences/pzc.DockActioner.plist",
    "~/Library/Saved Application State/pzc.DockActioner.savedState",
  ]
end
'''


def render_beta_cask(repo: str, version: str) -> str:
    return f'''cask "dock-actioner@beta" do
  version "{version}"
  sha256 :no_check

  on_arm do
    url "https://github.com/{repo}/releases/download/v#{{version}}/DockActioner-Beta-v#{{version}}-macos-arm64.zip"
  end

  on_intel do
    url "https://github.com/{repo}/releases/download/v#{{version}}/DockActioner-Beta-v#{{version}}-macos-x64.zip"
  end

  name "DockActioner Beta"
  desc "Beta channel for DockActioner"
  homepage "https://github.com/{repo}"

  livecheck do
    url "https://api.github.com/repos/{repo}/releases"
    strategy :json do |json|
      json
        .reject {{ |release| release["draft"] }}
        .map {{ |release| release["tag_name"] }}
    end
  end

  app "DockActioner Beta.app"

  zap trash: [
    "~/Library/Application Support/DockActioner Beta",
    "~/Library/Caches/pzc.DockActioner.beta",
    "~/Library/Preferences/pzc.DockActioner.beta.plist",
    "~/Library/Saved Application State/pzc.DockActioner.beta.savedState",
  ]
end
'''


def write_if_changed(path: Path, content: str) -> bool:
    existing = path.read_text(encoding="utf-8") if path.exists() else None
    if existing == content:
        return False
    path.write_text(content, encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--tap-path",
        type=Path,
        required=True,
        help="Path to local homebrew-tap checkout",
    )
    parser.add_argument(
        "--repo",
        default="apotenza92/dock-actioner",
        help="GitHub repository owner/name",
    )
    args = parser.parse_args()

    releases = fetch_releases(args.repo)
    stable = pick_latest(
        [release for release in releases if release.parsed.prerelease is None]
    )
    prerelease = pick_latest(
        [release for release in releases if release.parsed.prerelease is not None]
    )

    if stable is None and prerelease is None:
        print("No releases found; skipping Homebrew cask update.")
        return 0

    beta_track = None
    if stable is not None and prerelease is not None:
        stable_key = version_key(stable.parsed)
        prerelease_key_value = version_key(prerelease.parsed)
        beta_track = stable if stable_key >= prerelease_key_value else prerelease
    else:
        beta_track = stable or prerelease

    assert beta_track is not None

    casks_dir = args.tap_path / "Casks"
    casks_dir.mkdir(parents=True, exist_ok=True)

    stable_changed = False
    if stable is not None:
        stable_version = version_string(stable.parsed)
        stable_changed = write_if_changed(
            casks_dir / "dock-actioner.rb",
            render_stable_cask(args.repo, stable_version),
        )
        print(
            f"Stable cask -> {stable_version} ({'updated' if stable_changed else 'unchanged'})"
        )
    else:
        print("Stable cask unchanged (no stable releases yet)")

    beta_version = version_string(beta_track.parsed)
    beta_changed = write_if_changed(
        casks_dir / "dock-actioner@beta.rb", render_beta_cask(args.repo, beta_version)
    )
    print(f"Beta cask -> {beta_version} ({'updated' if beta_changed else 'unchanged'})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
