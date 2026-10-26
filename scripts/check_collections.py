#!/usr/bin/env python3
"""Compare installed Ansible collections against requirements.yml pins.

Runs `ansible-galaxy collection list` (respecting the active ansible.cfg and
ANSIBLE_COLLECTIONS_PATH) and reports every required collection that is
missing or installed at a different version than pinned.

Usage:
    python3 scripts/check_collections.py [--requirements requirements.yml]

Exits 0 when every pin is satisfied, 1 on missing/version drift, 2 when the
requirements file or the installed set cannot be determined.
"""

import argparse
import json
import subprocess
import sys

import yaml


def parse_requirements(data):
    """Return {collection name: pinned version} from parsed requirements.yml."""
    pins = {}
    for entry in data.get("collections") or []:
        pins[entry["name"]] = str(entry["version"])
    return pins


def effective_versions(galaxy_list):
    """Flatten `ansible-galaxy collection list --format json` output.

    The JSON maps each searched path to its collections. Ansible resolves a
    collection from the first path that provides it, so the first sighting of
    a name wins (e.g. ~/.ansible/collections over a distro bundle).
    """
    effective = {}
    for collections in galaxy_list.values():
        for name, info in collections.items():
            effective.setdefault(name, info["version"])
    return effective


def find_drift(required, installed):
    """Return sorted human-readable lines for missing or drifted pins."""
    drift = []
    for name in sorted(required):
        want = required[name]
        found = installed.get(name)
        if found is None:
            drift.append(f"{name}: missing (want {want})")
        elif found != want:
            drift.append(f"{name}: found {found}, want {want}")
    return drift


def list_installed():
    """Return the effective installed collections as {name: version}."""
    try:
        proc = subprocess.run(
            ["ansible-galaxy", "collection", "list", "--format", "json"],
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        print("Error: ansible-galaxy not found on PATH.", file=sys.stderr)
        sys.exit(2)
    if proc.returncode != 0:
        output = (proc.stderr + proc.stdout).strip()
        # Only the known empty result is determinate: ansible-galaxy (up to
        # core 2.19) exits non-zero with "None of the provided paths were
        # usable" when no configured path holds any collection (e.g. a bare
        # pip ansible-core). Everything else (config errors, permissions)
        # leaves the installed set undeterminable.
        if "None of the provided paths were usable" in output:
            print(f"Warning: {output}", file=sys.stderr)
            return {}
        print(
            f"Error: ansible-galaxy collection list failed (rc={proc.returncode}): {output}",
            file=sys.stderr,
        )
        sys.exit(2)
    try:
        return effective_versions(json.loads(proc.stdout))
    except json.JSONDecodeError as exc:
        print(f"Error: cannot parse ansible-galaxy output: {exc}", file=sys.stderr)
        sys.exit(2)


def main():
    parser = argparse.ArgumentParser(
        description="Verify installed Ansible collections match requirements.yml pins"
    )
    parser.add_argument(
        "--requirements",
        default="requirements.yml",
        help="Path to requirements.yml (default: requirements.yml)",
    )
    args = parser.parse_args()

    try:
        with open(args.requirements) as f:
            required = parse_requirements(yaml.safe_load(f) or {})
    except (OSError, yaml.YAMLError, KeyError, TypeError) as exc:
        print(f"Error: cannot read {args.requirements}: {exc}", file=sys.stderr)
        sys.exit(2)

    drift = find_drift(required, list_installed())
    if drift:
        print("Pinned Ansible collections missing or drifted:", file=sys.stderr)
        for line in drift:
            print(f"  {line}", file=sys.stderr)
        print("Run 'make collections' to install the pinned versions.", file=sys.stderr)
        sys.exit(1)
    print(f"Collections OK ({len(required)} pinned collections match)")


if __name__ == "__main__":
    main()
