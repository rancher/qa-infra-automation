#!/usr/bin/env python3
"""Display Rancher login information (URL, admin password, API token).

The credentials are written by the Rancher deployment playbooks, but the
location and format differ between environments:

* ``default`` (ansible/rancher/default-ha/rancher-playbook.yml, runs locally):
  - Token file: ``ansible/rancher/default-ha/generated.tfvars`` (tfvars)
  - Admin password: ``password`` key in ``.../vars.yaml``

* ``airgap`` (ansible/<distro>/shared/playbooks/deploy/rancher-helm-deploy-playbook.yml,
  runs on the bastion but writes the token locally):
  - Token file: ``tmp/rancher-admin-token.json`` (JSON)
  - Admin password: ``rancher_admin_password`` in ``inventory/group_vars/all.yml``
  - Public/internal hostnames: ``external_lb_hostname`` /
    ``internal_lb_hostname`` in ``inventory/inventory.yml``

Usage:
    python3 scripts/show_rancher_info.py --env default
    python3 scripts/show_rancher_info.py --env airgap --distro rke2

Paths are relative to the repo root (``--root``), but each input can be
overridden for testing.
"""

import argparse
import json
import os
import re
import sys

import yaml


def read_text(path):
    """Return file contents or None if missing."""
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return None


def read_yaml(path):
    """Parse a YAML file, returning {} if missing or empty."""
    txt = read_text(path)
    if txt is None:
        return {}
    return yaml.safe_load(txt) or {}


def parse_tfvars(path):
    """Parse a simple ``key = "value"`` tfvars file into a dict."""
    txt = read_text(path)
    if txt is None:
        return {}
    # Matches:  key = "value"   (double-quoted values only)
    return dict(re.findall(r'^\s*(\w+)\s*=\s*"([^"]*)"', txt, re.MULTILINE))


def load_default(root, token_file=None, vars_file=None):
    """Gather credentials for the default-ha deployment."""
    token_file = token_file or os.path.join(
        root, "ansible", "rancher", "default-ha", "generated.tfvars"
    )
    vars_file = vars_file or os.path.join(
        root, "ansible", "rancher", "default-ha", "vars.yaml"
    )

    vals = parse_tfvars(token_file)
    vars_data = read_yaml(vars_file)

    return {
        "token_file": token_file,
        "vars_file": vars_file,
        "url": vals.get("fqdn"),
        "token": vals.get("api_key"),
        "password": vars_data.get("password"),
        "username": "admin",
    }


def load_airgap(root, distro, token_file=None, vars_file=None, inventory=None):
    """Gather credentials for an airgap deployment."""
    token_file = token_file or os.path.join(root, "tmp", "rancher-admin-token.json")
    vars_file = vars_file or os.path.join(
        root, "ansible", distro, "airgap", "inventory", "group_vars", "all.yml"
    )
    inventory = inventory or os.path.join(
        root, "ansible", distro, "airgap", "inventory", "inventory.yml"
    )

    token_data = {}
    txt = read_text(token_file)
    if txt:
        try:
            token_data = json.loads(txt)
        except json.JSONDecodeError:
            token_data = {}

    # Hostnames live under all.vars in inventory.yml; password in group_vars.
    inv = read_yaml(inventory)
    inv_vars = ((inv.get("all") or {}).get("vars") or {}) if inv else {}
    group_vars = read_yaml(vars_file)

    ext = inv_vars.get("external_lb_hostname")
    intl = inv_vars.get("internal_lb_hostname")

    return {
        "token_file": token_file,
        "vars_file": vars_file,
        "inventory": inventory,
        "url": token_data.get("rancher_url"),
        "public_url": "https://" + ext if ext else None,
        "internal_url": "https://" + intl if intl else None,
        "token": token_data.get("token"),
        "password": group_vars.get("rancher_admin_password"),
        "username": "admin",
        "token_id": token_data.get("token_id"),
        "created_at": token_data.get("created_at"),
    }


def render(info, env, distro):
    """Print the credential summary; return an exit code."""
    found = bool(info.get("url") or info.get("token"))

    print("============================================================")
    print("  RANCHER LOGIN INFORMATION  ({} / {})".format(distro, env))
    print("============================================================")
    print()

    if info.get("url"):
        print("  Access URL:     {}".format(info["url"]))
    if info.get("public_url") and info["public_url"] != info.get("url"):
        print("  Public URL:     {}".format(info["public_url"]))
    if info.get("internal_url") and info["internal_url"] != info.get("url"):
        print("  Internal URL:   {}".format(info["internal_url"]))
    if not info.get("url"):
        print("  Access URL:     <not found>")
    print()

    print("  Admin Username: {}".format(info.get("username") or "admin"))
    print("  Admin Password: {}".format(info.get("password") or "<not found>"))
    print("  API Token:      {}".format(info.get("token") or "<not found>"))
    print()

    if info.get("token_id"):
        print("  Token ID:       {}".format(info["token_id"]))
    if info.get("created_at"):
        print("  Token Created:  {}".format(info["created_at"]))

    print("  Token file:     {}".format(info.get("token_file")))
    print("============================================================")
    print()

    if not found:
        print("No Rancher credentials found. Has Rancher been deployed?")
        print("Run: make rancher")
        print()
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description="Display Rancher login information")
    parser.add_argument("--env", default="default", choices=["default", "airgap"],
                        help="Deployment environment (default: %(default)s)")
    parser.add_argument("--distro", default="rke2",
                        help="Kubernetes distribution (default: %(default)s)")
    parser.add_argument("--root", default=os.getcwd(),
                        help="Repository root (default: %(default)s)")
    parser.add_argument("--token-file", help="Override token file path")
    parser.add_argument("--vars-file", help="Override vars file path")
    parser.add_argument("--inventory", help="Override inventory.yml path (airgap)")
    args = parser.parse_args()

    if args.env == "airgap":
        info = load_airgap(args.root, args.distro,
                           token_file=args.token_file,
                           vars_file=args.vars_file,
                           inventory=args.inventory)
    else:
        info = load_default(args.root,
                            token_file=args.token_file,
                            vars_file=args.vars_file)

    sys.exit(render(info, args.env, args.distro))


if __name__ == "__main__":
    main()
