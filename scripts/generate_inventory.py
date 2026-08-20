#!/usr/bin/env python3
"""Generate Ansible static inventory from Tofu JSON output.

Usage:
    # From live Tofu output:
    tofu -chdir=<module_dir> output -raw cluster_nodes_json > /tmp/nodes.json
    python3 scripts/generate_inventory.py \\
        --input /tmp/nodes.json \\
        --distro rke2 --env default \\
        --output-dir ansible/rke2/default/inventory

    # From live airgap Tofu output:
    tofu -chdir=tofu/aws/modules/airgap output -raw airgap_inventory_json > /tmp/airgap.json
    python3 scripts/generate_inventory.py \\
        --input /tmp/airgap.json \\
        --distro rke2 --env airgap \\
        --output-dir ansible/rke2/airgap/inventory

    # Standalone with fixture (no Tofu needed):
    python3 scripts/generate_inventory.py \\
        --input tests/fixtures/rke2_single_master.json \\
        --distro rke2 --env default \\
        --output-dir /tmp/test-inventory
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

import yaml


def load_json(path: str) -> dict:
    with open(path) as f:
        content = f.read().strip()
    if not content:
        print(
            f"Error: {path} is empty. Did 'tofu apply' complete successfully?",
            file=sys.stderr,
        )
        print(
            "Ensure the Tofu module defines the required output (cluster_nodes_json or airgap_inventory_json).",
            file=sys.stderr,
        )
        sys.exit(1)
    try:
        return json.loads(content)
    except json.JSONDecodeError as e:
        print(f"Error: Failed to parse JSON from {path}: {e}", file=sys.stderr)
        print(f"  File content (first 200 chars): {content[:200]}", file=sys.stderr)
        print(
            "This usually means 'tofu output' returned an error or no data.",
            file=sys.stderr,
        )
        print("Run 'tofu apply' first, then retry.", file=sys.stderr)
        sys.exit(1)


def load_schema(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def node_os(node: dict) -> str:
    """OS of a node. `os` is optional in the cluster_nodes contract — providers
    that predate Windows support omit it entirely, so absent means linux."""
    return node.get("os") or "linux"


def validate_cluster_nodes(data: dict) -> None:
    required_metadata = {"kube_api_host", "fqdn", "ssh_user"}
    missing = required_metadata - set(data.get("metadata", {}).keys())
    if missing:
        raise ValueError(f"cluster_nodes JSON missing metadata fields: {missing}")

    known_roles = {"etcd", "cp", "worker"}
    for node in data.get("nodes", []):
        unknown = set(node.get("roles", [])) - known_roles
        if unknown:
            raise ValueError(
                f"Node '{node['name']}' has unknown roles: {unknown}. "
                f"Known roles: {known_roles}"
            )
        for field in ("name", "roles", "public_ip", "private_ip"):
            if field not in node:
                raise ValueError(f"Node missing required field '{field}': {node}")

        known_os = {"linux", "windows"}
        if node_os(node) not in known_os:
            raise ValueError(
                f"Node '{node['name']}' has unknown os '{node['os']}'. "
                f"Known values: {known_os} (omit the field for linux)"
            )
        # Windows is agent-only in RKE2 — a cp/etcd Windows node cannot exist.
        if node_os(node) == "windows" and {"cp", "etcd"} & set(node.get("roles", [])):
            raise ValueError(
                f"Windows node '{node['name']}' has roles {node['roles']}; "
                "Windows nodes can only be workers (RKE2 has no Windows server role)."
            )


def validate_airgap(data: dict) -> None:
    required = {
        "bastion_host",
        "ssh_key",
        "ssh_user",
        "external_lb_hostname",
        "internal_lb_hostname",
        "node_groups",
    }
    missing = required - set(data.keys())
    if missing:
        raise ValueError(f"airgap JSON missing fields: {missing}")


def warn_if_k3s_needs_datastore(distro: str, data: dict) -> None:
    """Warn when K3s topology has no etcd — requires external datastore via server_flags."""
    if distro != "k3s":
        return
    if any("etcd" in n.get("roles", []) for n in data.get("nodes", [])):
        return
    print(
        "WARNING: K3s topology has no etcd-role node — set `datastore-endpoint: ...` "
        "via `server_flags` in vars.yaml or cluster-init will fail.",
        file=sys.stderr,
    )


def generate_cluster_nodes_inventory(data: dict, schema_cfg: dict) -> str:
    """Generate inventory YAML for cluster_nodes input type."""
    metadata = data["metadata"]
    nodes = data["nodes"]
    ip_field = schema_cfg.get("ip_field", "public_ip")
    default_key = metadata.get("ssh_private_key")
    groups_cfg = schema_cfg.get("groups", {})

    # Build groups: `roles` matches any listed role; `roles_priority` tries each set in order and stops on first match.
    # An optional `os` on the group restricts it to nodes of that OS; groups
    # without it match any OS (the airgap path and older schemas rely on that).
    groups: dict[str, list[dict]] = {name: [] for name in groups_cfg}

    for group_name, group_def in groups_cfg.items():
        wanted_os = group_def.get("os")
        candidates = [
            n for n in nodes if wanted_os is None or node_os(n) == wanted_os
        ]
        roles_priority = group_def.get("roles_priority")
        if roles_priority:
            for role_set in roles_priority:
                required = set(role_set)
                matched = [n for n in candidates if required & set(n["roles"])]
                if matched:
                    groups[group_name] = matched

                    break
        else:
            required = set(group_def.get("roles", []))
            groups[group_name] = [n for n in candidates if required & set(n["roles"])]

    # Apply first_only constraint
    for group_name, group_def in groups_cfg.items():
        if group_def.get("first_only") and groups[group_name]:
            groups[group_name] = [groups[group_name][0]]

    # Ensure mutual exclusivity: each node belongs to only one group (first match wins)
    node_to_group: dict[str, str] = {}
    for group_name, group_nodes in groups.items():
        for n in group_nodes:
            node_to_group.setdefault(n["name"], group_name)

    # A node that matched no group would silently vanish from every play. The
    # common cause is a windows node in a schema with no windows group (k3s).
    ungrouped = [n["name"] for n in nodes if n["name"] not in node_to_group]
    if ungrouped:
        raise ValueError(
            f"Nodes matched no inventory group: {ungrouped}. Check their roles/os "
            f"against the groups defined for this distro/env in the schema "
            f"({sorted(groups_cfg)})."
        )

    # Rebuild groups with mutually exclusive membership
    groups = {name: [] for name in groups_cfg}
    for node_name, group_name in node_to_group.items():
        node = next(n for n in nodes if n["name"] == node_name)
        groups[group_name].append(node)

    # Build inventory structure
    inventory: dict = {
        "all": {
            "vars": {
                "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
                "ansible_user": metadata["ssh_user"],
                "kube_api_host": metadata["kube_api_host"],
                "fqdn": metadata["fqdn"],
            },
            "hosts": {},
            "children": {},
        }
    }

    if default_key:
        inventory["all"]["vars"]["ansible_ssh_private_key_file"] = default_key

    # Create reverse mapping: node name -> group for role determination
    node_to_group: dict[str, str] = {}
    for group_name, group_nodes in groups.items():
        for n in group_nodes:
            node_to_group[n["name"]] = group_name

    # Add all nodes to the 'all' hosts section
    for node in nodes:
        node_roles = node["roles"]
        os_name = node_os(node)
        group = node_to_group.get(node["name"])
        if group == "master":
            node_type = "master"
        elif any(r in node_roles for r in ("cp", "etcd")):
            node_type = "server"
        else:
            node_type = "agent"
        host_entry = {
            "ansible_host": node[ip_field],
            "node_roles": node_roles,
            "node_type": node_type,
            "node_os": os_name,
        }

        if os_name == "windows":
            # Ansible reaches Windows over OpenSSH with PowerShell as the remote
            # shell (the Tofu user_data sets that up). No become — the win_*
            # modules already run as the connecting Administrator — and no
            # pipelining, which is POSIX-only and breaks them.
            host_entry["ansible_user"] = node.get("ssh_user", "Administrator")
            host_entry["ansible_connection"] = "ssh"
            host_entry["ansible_shell_type"] = "powershell"
            host_entry["ansible_become"] = False
            host_entry["ansible_pipelining"] = False

        node_key = node.get("ssh_private_key")
        if node_key:
            host_entry["ansible_ssh_private_key_file"] = node_key
        elif default_key:
            host_entry["ansible_ssh_private_key_file"] = default_key

        inventory["all"]["hosts"][node["name"]] = host_entry

    # Add named groups. Empty ones are emitted too, so that a host pattern which
    # excludes a group -- `all:!windows_workers` in the RKE2 playbook -- does not
    # warn "Could not match supplied host pattern" on Linux-only clusters.
    for group_name, group_nodes in groups.items():
        inventory["all"]["children"][group_name] = {
            "hosts": {
                node["name"]: {"ansible_host": node[ip_field]} for node in group_nodes
            }
        }

    return yaml.dump(inventory, default_flow_style=False, sort_keys=False)


def generate_airgap_inventory(data: dict) -> str:
    """Generate inventory YAML for airgap input type."""
    bastion_host = data["bastion_host"]
    registry_host = data.get("registry_host")
    ssh_key = data["ssh_key"]
    ssh_user = data["ssh_user"]
    external_lb = data["external_lb_hostname"]
    internal_lb = data["internal_lb_hostname"]
    node_groups = data["node_groups"]

    inventory: dict = {
        "all": {
            "vars": {
                "ssh_private_key_file": ssh_key,
                "ansible_ssh_private_key_file": "{{ ssh_private_key_file }}",
                "bastion_user": ssh_user,
                "bastion_host": bastion_host,
                "external_lb_hostname": external_lb,
                "internal_lb_hostname": internal_lb,
            },
            "children": {
                "bastion": {
                    "hosts": {
                        "bastion-node": {
                            "ansible_host": "{{ bastion_host }}",
                            "ansible_user": "{{ bastion_user }}",
                            "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
                        }
                    }
                },
                "airgap_nodes": {
                    "vars": {
                        "ansible_user": ssh_user,
                        "ansible_ssh_common_args": (
                            "-o ProxyCommand='ssh -i {{ ssh_private_key_file }} -W %h:%p "
                            "{{ bastion_user }}@{{ bastion_host }} "
                            "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' "
                            "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
                        ),
                        "bastion_ip": "{{ bastion_host }}",
                    },
                    "children": {
                        group_name: {
                            "hosts": {
                                f"{group_name}_node_{i + 1}": {"ansible_host": ip}
                                for i, ip in enumerate(ips)
                            }
                        }
                        for group_name, ips in node_groups.items()
                    },
                },
            },
        }
    }

    if registry_host:
        inventory["all"]["vars"]["registry_host"] = registry_host
        inventory["all"]["children"]["registry"] = {
            "hosts": {
                "registry-node": {
                    "ansible_host": "{{ registry_host }}",
                    "ansible_user": "{{ bastion_user }}",
                    "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
                }
            }
        }

    return yaml.dump(inventory, default_flow_style=False, sort_keys=False)


def write_manifest(output_dir: str, input_path: str, inventory_path: str) -> None:
    with open(input_path, "rb") as f:
        input_bytes = f.read()
    with open(inventory_path, "rb") as f:
        inventory_bytes = f.read()

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "input_checksum": hashlib.sha256(input_bytes).hexdigest(),
        "inventory_checksum": hashlib.sha256(inventory_bytes).hexdigest(),
        "input_file": os.path.abspath(input_path),
        "inventory_file": os.path.abspath(inventory_path),
    }

    manifest_path = os.path.join(output_dir, ".inventory-manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"Manifest written to {manifest_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Ansible inventory from Tofu JSON output"
    )
    parser.add_argument("--input", required=True, help="Path to Tofu JSON output file")
    parser.add_argument(
        "--distro", required=True, choices=["rke2", "k3s"], help="Kubernetes distro"
    )
    parser.add_argument(
        "--env",
        required=True,
        choices=["airgap", "default", "proxy"],
        help="Environment type",
    )
    parser.add_argument(
        "--schema",
        default="ansible/_inventory-schema.yaml",
        help="Path to inventory schema YAML",
    )
    parser.add_argument(
        "--output-dir", required=True, help="Directory to write inventory.yml into"
    )
    args = parser.parse_args()

    data = load_json(args.input)

    input_type = data.get("type")
    if not input_type:
        print(
            "Error: JSON input missing 'type' field (expected 'cluster_nodes' or 'airgap')",
            file=sys.stderr,
        )
        sys.exit(1)

    schema = load_schema(args.schema)
    distro_schema = schema.get(args.distro, {}).get(args.env)
    if distro_schema is None:
        print(
            f"Error: No schema entry for distro='{args.distro}' env='{args.env}'",
            file=sys.stderr,
        )
        sys.exit(1)

    if input_type == "cluster_nodes":
        validate_cluster_nodes(data)
        warn_if_k3s_needs_datastore(args.distro, data)
        inventory_yaml = generate_cluster_nodes_inventory(data, distro_schema)
    elif input_type == "airgap":
        validate_airgap(data)
        inventory_yaml = generate_airgap_inventory(data)
    else:
        print(f"Error: Unknown input type '{input_type}'", file=sys.stderr)
        sys.exit(1)

    os.makedirs(args.output_dir, exist_ok=True)
    inventory_path = os.path.join(args.output_dir, "inventory.yml")
    with open(inventory_path, "w") as f:
        f.write(inventory_yaml)
    print(f"Inventory written to {inventory_path}")

    write_manifest(args.output_dir, args.input, inventory_path)


if __name__ == "__main__":
    main()
