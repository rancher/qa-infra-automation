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
        print(f"Error: {path} is empty. Did 'tofu apply' complete successfully?", file=sys.stderr)
        print("Ensure the Tofu module defines the required output (cluster_nodes_json or airgap_inventory_json).", file=sys.stderr)
        sys.exit(1)
    try:
        return json.loads(content)
    except json.JSONDecodeError as e:
        print(f"Error: Failed to parse JSON from {path}: {e}", file=sys.stderr)
        print(f"  File content (first 200 chars): {content[:200]}", file=sys.stderr)
        print("This usually means 'tofu output' returned an error or no data.", file=sys.stderr)
        print("Run 'tofu apply' first, then retry.", file=sys.stderr)
        sys.exit(1)


def load_schema(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


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


def validate_airgap(data: dict) -> None:
    required = {"bastion_host", "ssh_key", "ssh_user", "external_lb_hostname",
                "internal_lb_hostname", "node_groups"}
    missing = required - set(data.keys())
    if missing:
        raise ValueError(f"airgap JSON missing fields: {missing}")


def generate_cluster_nodes_inventory(data: dict, schema_cfg: dict) -> str:
    """Generate inventory YAML for cluster_nodes input type."""
    metadata = data["metadata"]
    nodes = data["nodes"]
    ip_field = schema_cfg.get("ip_field", "public_ip")
    groups_cfg = schema_cfg.get("groups", {})

    # Build groups: each node is assigned to groups based on its roles
    groups: dict[str, list[dict]] = {name: [] for name in groups_cfg}

    for node in nodes:
        node_roles = set(node["roles"])
        for group_name, group_def in groups_cfg.items():
            required_roles = set(group_def.get("roles", []))
            if required_roles & node_roles:  # node has at least one matching role
                groups[group_name].append(node)

    # Apply first_only constraint
    for group_name, group_def in groups_cfg.items():
        if group_def.get("first_only") and groups[group_name]:
            groups[group_name] = [groups[group_name][0]]

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

    # Map each node to its primary group (first match wins)
    node_to_group: dict[str, str] = {}
    for group_name, group_nodes in groups.items():
        for n in group_nodes:
            node_to_group.setdefault(n["name"], group_name)

    # Add all nodes to the 'all' hosts section
    for node in nodes:
        node_roles = node["roles"]
        group = node_to_group.get(node["name"])
        if group == "master":
            rke2_node_role = "master"
        elif any(r in node_roles for r in ("cp", "etcd")):
            rke2_node_role = "server"
        else:
            rke2_node_role = "agent"
        inventory["all"]["hosts"][node["name"]] = {
            "ansible_host": node[ip_field],
            "node_roles": node_roles,
            "rke2_node_role": rke2_node_role,
        }

    # Add named groups
    for group_name, group_nodes in groups.items():
        if not group_nodes:
            continue
        inventory["all"]["children"][group_name] = {
            "hosts": {
                node["name"]: {"ansible_host": node[ip_field]}
                for node in group_nodes
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
    parser = argparse.ArgumentParser(description="Generate Ansible inventory from Tofu JSON output")
    parser.add_argument("--input", required=True, help="Path to Tofu JSON output file")
    parser.add_argument("--distro", required=True, choices=["rke2", "k3s"], help="Kubernetes distro")
    parser.add_argument("--env", required=True, choices=["airgap", "default", "proxy"], help="Environment type")
    parser.add_argument("--schema", default="ansible/_inventory-schema.yaml", help="Path to inventory schema YAML")
    parser.add_argument("--output-dir", required=True, help="Directory to write inventory.yml into")
    args = parser.parse_args()

    data = load_json(args.input)

    input_type = data.get("type")
    if not input_type:
        print("Error: JSON input missing 'type' field (expected 'cluster_nodes' or 'airgap')", file=sys.stderr)
        sys.exit(1)

    schema = load_schema(args.schema)
    distro_schema = schema.get(args.distro, {}).get(args.env)
    if distro_schema is None:
        print(f"Error: No schema entry for distro='{args.distro}' env='{args.env}'", file=sys.stderr)
        sys.exit(1)

    if input_type == "cluster_nodes":
        validate_cluster_nodes(data)
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
