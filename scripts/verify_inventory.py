#!/usr/bin/env python3
"""Verify that a generated inventory is not stale.

Reads the .inventory-manifest.json written by generate-inventory.py
and compares checksums to detect drift.

Usage:
    python3 scripts/verify-inventory.py \\
        --manifest ansible/rke2/airgap/inventory/.inventory-manifest.json

Exits 0 if inventory is fresh, non-zero if stale or manifest is missing.
"""

import argparse
import hashlib
import json
import os
import sys


def file_checksum(path: str) -> str:
    with open(path) as f:
        return hashlib.sha256(f.read().encode()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify Ansible inventory freshness")
    parser.add_argument("--manifest", required=True, help="Path to .inventory-manifest.json")
    args = parser.parse_args()

    if not os.path.exists(args.manifest):
        print(f"Error: Manifest not found at {args.manifest}", file=sys.stderr)
        print("Run 'make infra-up' to generate the inventory.", file=sys.stderr)
        sys.exit(1)

    with open(args.manifest) as f:
        manifest = json.load(f)

    inventory_path = manifest["inventory_file"]
    stored_checksum = manifest["inventory_checksum"]
    generated_at = manifest["generated_at"]

    if not os.path.exists(inventory_path):
        print(f"Error: Inventory file not found: {inventory_path}", file=sys.stderr)
        sys.exit(1)

    current_checksum = file_checksum(inventory_path)
    if current_checksum != stored_checksum:
        print(f"Error: Inventory has been modified since it was generated.", file=sys.stderr)
        print(f"  Generated: {generated_at}", file=sys.stderr)
        print(f"  File: {inventory_path}", file=sys.stderr)
        print("Run 'make infra-up' to regenerate the inventory.", file=sys.stderr)
        sys.exit(2)

    print(f"Inventory OK (generated {generated_at})")
    sys.exit(0)


if __name__ == "__main__":
    main()
