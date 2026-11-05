#!/usr/bin/env python3
"""Resolve a Rancher server chart version from a Helm repository index.

Used by `make rancher-upgrade` (empty/`latest` target resolves at runtime to
the newest released chart) and reusable from pipelines to resolve the deploy
side (`--line 2.14` answers "latest 2.14.x patch"). Prints JSON on stdout:

    {"chart_version": "2.14.5", "image_tag": "v2.14.5", "created": "..."}

Selection reads the repo's index.yaml over HTTP rather than `helm search`
because search needs `helm repo add` first and truncates its table output.
Version ordering and the final/line classification are shared with the
dashboard-e2e pipeline through ansible/testing/dashboard-e2e/filter_plugins/
rancher_charts.py, so both resolvers cannot drift apart.

Exit codes: 0 on a match, 1 when nothing in the index matches the request.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

import yaml

_REPO_ROOT = Path(__file__).resolve().parents[1]
_FILTERS_PATH = _REPO_ROOT / "ansible" / "testing" / "dashboard-e2e" / "filter_plugins" / "rancher_charts.py"

_spec = importlib.util.spec_from_file_location("rancher_charts", _FILTERS_PATH)
rancher_charts = importlib.util.module_from_spec(_spec)
sys.modules["rancher_charts"] = rancher_charts
_spec.loader.exec_module(rancher_charts)

_FINAL = re.compile(r"^\d+\.\d+\.\d+$")
_PRERELEASE = re.compile(r"^\d+\.\d+\.\d+-[a-z]+\.?\d*$")


def load_entries(source: str) -> list[dict]:
    """`entries.rancher` from an index.yaml URL or local file path."""
    if source.startswith(("http://", "https://")):
        try:
            from urllib.request import urlopen

            with urlopen(source, timeout=30) as response:
                content = response.read().decode("utf-8")
        except OSError as error:
            raise SystemExit(f"error: could not fetch {source}: {error}")
    else:
        content = Path(source).read_text(encoding="utf-8")

    try:
        index = yaml.safe_load(content) or {}
    except yaml.YAMLError as error:
        raise SystemExit(f"error: {source} is not valid YAML: {error}")

    return ((index.get("entries") or {}).get("rancher")) or []


def _eligible(version: str, include_prerelease: bool) -> bool:
    """Finals always; rc/alpha shapes only when asked; head builds never."""
    if rancher_charts._is_head(version):
        return False
    if _FINAL.match(version):
        return True
    return bool(include_prerelease and _PRERELEASE.match(version))


def select_version(entries: list[dict], line: str | None = None, include_prerelease: bool = False) -> dict:
    """The newest matching chart entry, or `{}` when nothing matches.

    Finals only by default: the question is what shipped. With
    `include_prerelease`, rc/alpha shapes of a newer line may win, which serves
    the pre-release channels; head builds are never selected because a fixed
    input must not resolve to a different build every run.
    """
    candidates = [c for c in entries if _eligible(c.get("version") or "", include_prerelease)]
    if line:
        wanted = line.lstrip("v")
        candidates = [
            c
            for c in candidates
            if rancher_charts._line_of(c.get("version", "")) == wanted
        ]
    if not candidates:
        return {}
    return max(candidates, key=lambda c: rancher_charts._sort_key(c.get("version", "")))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo-url", required=True, help="Helm repository, e.g. https://releases.rancher.com/server-charts/latest")
    parser.add_argument("--line", help="Restrict to one release line, e.g. 2.14 (highest final patch of that line)")
    parser.add_argument("--include-prerelease", action="store_true", help="Allow rc/alpha shapes; never head builds")
    parser.add_argument("--index-file", help="Read the index from this file instead of HTTP (offline/airgap use)")
    args = parser.parse_args(argv)

    source = args.index_file or f"{args.repo_url.rstrip('/')}/index.yaml"
    entry = select_version(load_entries(source), line=args.line, include_prerelease=args.include_prerelease)
    if not entry:
        print(
            f"error: no {'final ' if not args.include_prerelease else ''}release"
            f"{' on line ' + args.line if args.line else ''} found in {source}",
            file=sys.stderr,
        )
        return 1

    chart_version = entry["version"]
    print(
        json.dumps(
            {
                "chart_version": chart_version,
                "image_tag": f"v{chart_version}",
                "created": entry.get("created", ""),
                "source": source,
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
