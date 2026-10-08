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

def validate_dualstack(data: dict) -> None:
    """Validate the dual-stack / IPv6-only payload.

    Bastion metadata is optional: BYO inventories and public-IP topologies
    reach the nodes directly.
    """
    required_metadata = {"kube_api_host", "fqdn", "ssh_user"}
    missing = required_metadata - set(data.get("metadata", {}).keys())
    if missing:
        raise ValueError(f"dualstack JSON missing metadata fields: {missing}")

    known_roles = {"etcd", "cp", "worker"}
    for node in data.get("nodes", []):
        unknown = set(node.get("roles", [])) - known_roles
        if unknown:
            raise ValueError(
                f"Node '{node['name']}' has unknown roles: {unknown}. "
                f"Known roles: {known_roles}"
            )
        for field in ("name", "roles", "public_ip", "private_ip", "ipv6"):
            if field not in node:
                raise ValueError(f"Node missing required field '{field}': {node}")


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


def build_groups(nodes: list[dict], groups_cfg: dict) -> dict[str, list[dict]]:
    """Map nodes onto the schema's Ansible groups.

    `roles` matches any listed role; `roles_priority` tries each role set in
    order and stops at the first match (so a cp-only topology still yields a
    `master`). Group membership is mutually exclusive, first match wins.
    """
    groups: dict[str, list[dict]] = {name: [] for name in groups_cfg}

    for group_name, group_def in groups_cfg.items():
        roles_priority = group_def.get("roles_priority")
        if roles_priority:
            for role_set in roles_priority:
                required = set(role_set)
                matched = [n for n in nodes if required & set(n["roles"])]
                if matched:
                    groups[group_name] = matched
                    break
        else:
            required = set(group_def.get("roles", []))
            groups[group_name] = [n for n in nodes if required & set(n["roles"])]

    for group_name, group_def in groups_cfg.items():
        if group_def.get("first_only") and groups[group_name]:
            groups[group_name] = [groups[group_name][0]]

    node_to_group: dict[str, str] = {}
    for group_name, group_nodes in groups.items():
        for n in group_nodes:
            node_to_group.setdefault(n["name"], group_name)

    groups = {name: [] for name in groups_cfg}
    for node_name, group_name in node_to_group.items():
        node = next(n for n in nodes if n["name"] == node_name)
        groups[group_name].append(node)

    return groups


def node_role_label(node: dict, group: str | None) -> str:
    if group == "master":
        return "master"
    if any(r in node["roles"] for r in ("cp", "etcd")):
        return "server"
    return "agent"


def generate_cluster_nodes_inventory(data: dict, schema_cfg: dict) -> str:
    """Generate inventory YAML for cluster_nodes input type."""
    metadata = data["metadata"]
    nodes = data["nodes"]
    ip_field = schema_cfg.get("ip_field", "public_ip")
    default_key = metadata.get("ssh_private_key")
    groups_cfg = schema_cfg.get("groups", {})

    groups = build_groups(nodes, groups_cfg)

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

    # Ansible warns against host and group sharing the same name.
    group_names = set(groups_cfg)
    existing_names = {node["name"] for node in nodes}
    host_name_map: dict[str, str] = {}
    for name in existing_names:
        if name not in group_names:
            continue
        candidate = f"{name}-node"
        suffix = 1
        while candidate in existing_names or candidate in group_names or candidate in host_name_map.values():
            suffix += 1
            candidate = f"{name}-node-{suffix}"
        host_name_map[name] = candidate

    def host_key(node_name: str) -> str:
        return host_name_map.get(node_name, node_name)

    # Add all nodes to the 'all' hosts section
    for node in nodes:
        host_entry = {
            "ansible_host": node[ip_field],
            "node_roles": node["roles"],
            "rke2_node_role": node_role_label(node, node_to_group.get(node["name"])),
        }

        node_key = node.get("ssh_private_key")
        if node_key:
            host_entry["ansible_ssh_private_key_file"] = node_key
        elif default_key:
            host_entry["ansible_ssh_private_key_file"] = default_key

        inventory["all"]["hosts"][host_key(node["name"])] = host_entry

    # Add named groups
    for group_name, group_nodes in groups.items():
        if not group_nodes:
            continue
        inventory["all"]["children"][group_name] = {
            "hosts": {
                host_key(node["name"]): {"ansible_host": node[ip_field]}
                for node in group_nodes
            }
        }

    return yaml.dump(inventory, default_flow_style=False, sort_keys=False)


def generate_dualstack_inventory(data: dict, schema_cfg: dict) -> str:
    """Generate inventory YAML for the dual-stack and IPv6-only environments.

    Both publish `ansible_host_ipv6` alongside `ansible_host` and may route SSH
    through a bastion; `ip_field` in the schema decides which family Ansible
    connects over (public_ip for dual-stack, ipv6 for IPv6-only).
    """
    metadata = data["metadata"]
    nodes = data["nodes"]
    ip_field = schema_cfg.get("ip_field", "public_ip")
    default_key = metadata.get("ssh_private_key")
    groups_cfg = schema_cfg.get("groups", {})
    bastion_ip = metadata.get("bastion_ip", "")
    bastion_user = metadata.get("bastion_user", metadata.get("ssh_user"))

    groups = build_groups(nodes, groups_cfg)

    # %h is bracketed so the ProxyCommand can parse IPv6 node addresses.
    if bastion_ip:
        common_args = (
            "-o ProxyCommand='ssh -i {{ ansible_ssh_private_key_file }} -W \"[%h]:%p\" "
            "{{ bastion_user }}@{{ bastion_host }} "
            "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' "
            "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        )
    else:
        common_args = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    inventory: dict = {
        "all": {
            "vars": {
                "ansible_ssh_common_args": common_args,
                "ansible_user": metadata["ssh_user"],
                "kube_api_host": metadata["kube_api_host"],
                "fqdn": metadata["fqdn"],
            },
            "hosts": {},
            "children": {},
        }
    }

    if bastion_ip:
        inventory["all"]["vars"]["bastion_host"] = bastion_ip
        inventory["all"]["vars"]["bastion_user"] = bastion_user
        inventory["all"]["vars"]["bastion_dns"] = metadata.get("bastion_dns", "")
        inventory["all"]["children"]["bastion"] = {
            "hosts": {
                "bastion-node": {
                    "ansible_host": "{{ bastion_host }}",
                    "ansible_user": "{{ bastion_user }}",
                    "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
                }
            }
        }

    if default_key:
        inventory["all"]["vars"]["ansible_ssh_private_key_file"] = default_key

    node_to_group: dict[str, str] = {}
    for group_name, group_nodes in groups.items():
        for n in group_nodes:
            node_to_group[n["name"]] = group_name

    def connect_ip(node: dict) -> str:
        return node.get(ip_field) or node.get("ipv6", "")

    for node in nodes:
        host_entry = {
            "ansible_host": connect_ip(node),
            "ansible_host_ipv6": node.get("ipv6", ""),
            "node_roles": node["roles"],
            "rke2_node_role": node_role_label(node, node_to_group.get(node["name"])),
        }

        node_key = node.get("ssh_private_key")
        if node_key:
            host_entry["ansible_ssh_private_key_file"] = node_key
        elif default_key:
            host_entry["ansible_ssh_private_key_file"] = default_key

        inventory["all"]["hosts"][node["name"]] = host_entry

    for group_name, group_nodes in groups.items():
        if not group_nodes:
            continue
        inventory["all"]["children"][group_name] = {
            "hosts": {
                node["name"]: {
                    "ansible_host": connect_ip(node),
                    "ansible_host_ipv6": node.get("ipv6", ""),
                }
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

    # Omitted rather than emitted as null when the LB/route53 modules are off:
    # Ansible's default() only fires on undefined, so a null would render as "None".
    if external_lb:
        inventory["all"]["vars"]["external_lb_hostname"] = external_lb
    if internal_lb:
        inventory["all"]["vars"]["internal_lb_hostname"] = internal_lb

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
        choices=["airgap", "default", "proxy", "dualstack", "ipv6"],
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
            f"Error: No schema entry for distro='{args.distro}' env='{args.env}'. "
            f"Supported envs for '{args.distro}': "
            f"{sorted(schema.get(args.distro, {}))}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Airgap payloads carry no 'nodes' key, so the etcd check would always warn.
    if input_type != "airgap":
        warn_if_k3s_needs_datastore(args.distro, data)

    if args.env in {"dualstack", "ipv6"}:
        if input_type not in {"cluster_nodes", "dualstack"}:
            print(
                f"Error: env='{args.env}' expects a 'cluster_nodes' or 'dualstack' "
                f"input type, got '{input_type}'",
                file=sys.stderr,
            )
            sys.exit(1)
        validate_dualstack(data)
        inventory_yaml = generate_dualstack_inventory(data, distro_schema)
    elif input_type == "cluster_nodes":
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
