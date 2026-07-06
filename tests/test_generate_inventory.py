"""Unit tests for scripts/generate_inventory.py"""

import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from scripts.generate_inventory import (
    generate_airgap_inventory,
    generate_cluster_nodes_inventory,
    validate_airgap,
    validate_cluster_nodes,
    warn_if_k3s_needs_datastore,
    write_manifest,
)

import yaml

SCHEMA_PATH = os.path.join(os.path.dirname(__file__), "..", "ansible", "_inventory-schema.yaml")
FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures")


def load_schema():
    with open(SCHEMA_PATH) as f:
        return yaml.safe_load(f)


def load_fixture(name):
    with open(os.path.join(FIXTURES_DIR, name)) as f:
        return json.load(f)


class TestValidateClusterNodes(unittest.TestCase):
    def test_valid_fixture_passes(self):
        data = load_fixture("rke2_single_master.json")
        validate_cluster_nodes(data)  # should not raise

    def test_missing_metadata_field_raises(self):
        data = load_fixture("rke2_single_master.json")
        del data["metadata"]["ssh_user"]
        with self.assertRaises(ValueError):
            validate_cluster_nodes(data)

    def test_unknown_role_raises(self):
        data = load_fixture("rke2_single_master.json")
        data["nodes"][0]["roles"] = ["invalid_role"]
        with self.assertRaises(ValueError):
            validate_cluster_nodes(data)

    def test_missing_node_field_raises(self):
        data = load_fixture("rke2_single_master.json")
        del data["nodes"][0]["public_ip"]
        with self.assertRaises(ValueError):
            validate_cluster_nodes(data)


class TestValidateAirgap(unittest.TestCase):
    def test_valid_fixture_passes(self):
        data = load_fixture("rke2_ha_airgap.json")
        validate_airgap(data)  # should not raise

    def test_missing_field_raises(self):
        data = load_fixture("rke2_ha_airgap.json")
        del data["bastion_host"]
        with self.assertRaises(ValueError):
            validate_airgap(data)


class TestK3sDatastoreWarning(unittest.TestCase):
    def capture_warning(self, distro, data):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            warn_if_k3s_needs_datastore(distro, data)
        return stderr.getvalue()

    def test_warns_for_k3s_without_etcd_node(self):
        data = load_fixture("k3s_external_datastore.json")
        warning = self.capture_warning("k3s", data)
        self.assertIn("K3s topology has no etcd-role node", warning)
        self.assertIn("datastore-endpoint", warning)

    def test_silent_for_k3s_with_etcd_node(self):
        data = load_fixture("k3s_split_role.json")
        self.assertEqual(self.capture_warning("k3s", data), "")

    def test_silent_for_non_k3s_without_etcd_node(self):
        data = load_fixture("k3s_external_datastore.json")
        self.assertEqual(self.capture_warning("rke2", data), "")


class TestGenerateClusterNodesInventory(unittest.TestCase):
    def setUp(self):
        self.schema = load_schema()

    def test_rke2_default_master_group(self):
        data = load_fixture("rke2_single_master.json")
        cfg = self.schema["rke2"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        self.assertIn("master", result["all"]["children"])
        master_hosts = result["all"]["children"]["master"]["hosts"]
        self.assertEqual(len(master_hosts), 1)
        self.assertIn("master", master_hosts)

    def test_rke2_default_uses_public_ip(self):
        data = load_fixture("rke2_single_master.json")
        cfg = self.schema["rke2"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        master_host = result["all"]["children"]["master"]["hosts"]["master"]
        self.assertEqual(master_host["ansible_host"], "1.2.3.4")

    def test_all_nodes_present_in_all_section(self):
        data = load_fixture("rke2_single_master.json")
        cfg = self.schema["rke2"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        self.assertEqual(len(result["all"]["hosts"]), 3)

    def test_k3s_default_groups(self):
        data = load_fixture("k3s_single_master.json")
        cfg = self.schema["k3s"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        children = result["all"]["children"]
        self.assertIn("master", children)
        self.assertIn("workers", children)
        self.assertEqual(len(children["master"]["hosts"]), 1)
        self.assertEqual(len(children["workers"]["hosts"]), 2)

    def test_k3s_single_master_has_etcd_and_cp(self):
        """K3s single-master canonical topology: master runs embedded etcd + cp
        on the same node. A cp-only master with no datastore-endpoint would
        not boot, so the fixture must include etcd."""
        data = load_fixture("k3s_single_master.json")
        cfg = self.schema["k3s"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        master_hosts = result["all"]["children"]["master"]["hosts"]
        self.assertEqual(list(master_hosts.keys()), ["master"])
        self.assertIn("etcd", result["all"]["hosts"]["master"]["node_roles"])
        self.assertIn("cp", result["all"]["hosts"]["master"]["node_roles"])

    def test_k3s_external_datastore_master_falls_back_to_cp(self):
        """K3s external-datastore topology (no etcd nodes): roles_priority must
        fall back from [etcd] to [cp] and pick the first cp node as master.
        Without this fallback the master group is empty and the play can't bootstrap."""
        data = load_fixture("k3s_external_datastore.json")
        cfg = self.schema["k3s"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        master_hosts = result["all"]["children"]["master"]["hosts"]
        self.assertEqual(list(master_hosts.keys()), ["cp-0"])
        self.assertEqual(result["all"]["hosts"]["cp-0"]["node_roles"], ["cp"])

    def test_k3s_split_role_master_is_first_etcd(self):
        """K3s split-role: when any etcd node exists, master must be one of
        them (not cp), because cluster-init bootstraps embedded etcd."""
        data = load_fixture("k3s_split_role.json")
        cfg = self.schema["k3s"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        master_hosts = result["all"]["children"]["master"]["hosts"]
        self.assertEqual(list(master_hosts.keys()), ["master"])
        # Master node in the fixture has roles=[etcd]
        self.assertEqual(result["all"]["hosts"]["master"]["node_roles"], ["etcd"])

    def test_k3s_split_role_servers_include_etcd_and_cp(self):
        """K3s split-role: servers group must include both remaining etcd
        and cp nodes (not just cp). Otherwise the play silently drops etcd
        nodes from the install."""
        data = load_fixture("k3s_split_role.json")
        cfg = self.schema["k3s"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        server_names = set(result["all"]["children"]["servers"]["hosts"].keys())
        self.assertEqual(server_names, {"etcd-1", "etcd-2", "cp-0", "cp-1"})

    def test_k3s_split_role_has_cp_host_for_kubeconfig_rewrite(self):
        """K3s split-role keeps kube_api_host on the etcd-only cluster-init
        node for joins, but the playbook can still select a cp-bearing host
        when rewriting the saved kubeconfig server URL."""
        data = load_fixture("k3s_split_role.json")
        cfg = self.schema["k3s"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))

        kube_api_host = result["all"]["vars"]["kube_api_host"]
        master_name = next(iter(result["all"]["children"]["master"]["hosts"]))
        master = result["all"]["hosts"][master_name]
        self.assertEqual(master["node_roles"], ["etcd"])
        self.assertEqual(master["ansible_host"], kube_api_host)

        cp_hosts = [
            host["ansible_host"]
            for host in result["all"]["hosts"].values()
            if "cp" in host["node_roles"]
        ]
        self.assertEqual(cp_hosts[0], "3.4.5.8")
        self.assertNotEqual(cp_hosts[0], kube_api_host)

    def test_worker_nodes_not_in_master_group(self):
        data = load_fixture("rke2_single_master.json")
        cfg = self.schema["rke2"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        master_hosts = result["all"]["children"]["master"]["hosts"]
        self.assertNotIn("worker-0", master_hosts)
        self.assertNotIn("worker-1", master_hosts)

    def test_rke2_node_role_master_for_master_group_node(self):
        data = load_fixture("rke2_single_master.json")
        cfg = self.schema["rke2"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        self.assertEqual(result["all"]["hosts"]["master"]["rke2_node_role"], "master")

    def test_rke2_node_role_agent_for_worker_nodes(self):
        data = load_fixture("rke2_single_master.json")
        cfg = self.schema["rke2"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        self.assertEqual(result["all"]["hosts"]["worker-0"]["rke2_node_role"], "agent")
        self.assertEqual(result["all"]["hosts"]["worker-1"]["rke2_node_role"], "agent")

    def test_rke2_node_role_server_for_cp_node_outside_master_group(self):
        # A node with cp/etcd roles that isn't picked as the master group node
        # should get rke2_node_role == 'server'
        data = load_fixture("rke2_single_master.json")
        data["nodes"].insert(1, {
            "name": "server-1",
            "roles": ["cp", "etcd"],
            "public_ip": "1.2.3.7",
            "private_ip": "10.0.1.4",
        })
        cfg = self.schema["rke2"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        self.assertEqual(result["all"]["hosts"]["server-1"]["rke2_node_role"], "server")

    def test_node_roles_is_list_not_string(self):
        data = load_fixture("rke2_single_master.json")
        cfg = self.schema["rke2"]["default"]
        result = yaml.safe_load(generate_cluster_nodes_inventory(data, cfg))
        for host_vars in result["all"]["hosts"].values():
            self.assertIsInstance(host_vars["node_roles"], list)


class TestGenerateAirgapInventory(unittest.TestCase):
    def test_bastion_group_present(self):
        data = load_fixture("rke2_ha_airgap.json")
        result = yaml.safe_load(generate_airgap_inventory(data))
        self.assertIn("bastion", result["all"]["children"])

    def test_airgap_nodes_group_present(self):
        data = load_fixture("rke2_ha_airgap.json")
        result = yaml.safe_load(generate_airgap_inventory(data))
        self.assertIn("airgap_nodes", result["all"]["children"])

    def test_node_groups_as_children_of_airgap_nodes(self):
        data = load_fixture("rke2_ha_airgap.json")
        result = yaml.safe_load(generate_airgap_inventory(data))
        airgap_children = result["all"]["children"]["airgap_nodes"]["children"]
        self.assertIn("server", airgap_children)
        self.assertIn("worker", airgap_children)

    def test_server_nodes_use_private_ips(self):
        data = load_fixture("rke2_ha_airgap.json")
        result = yaml.safe_load(generate_airgap_inventory(data))
        server_hosts = result["all"]["children"]["airgap_nodes"]["children"]["server"]["hosts"]
        # Private IPs come from node_groups in fixture
        ips = [h["ansible_host"] for h in server_hosts.values()]
        self.assertIn("10.0.1.1", ips)

    def test_registry_group_present_when_registry_host_set(self):
        data = load_fixture("rke2_ha_airgap.json")
        result = yaml.safe_load(generate_airgap_inventory(data))
        self.assertIn("registry", result["all"]["children"])

    def test_registry_group_absent_when_registry_host_null(self):
        data = load_fixture("rke2_ha_airgap.json")
        data["registry_host"] = None
        result = yaml.safe_load(generate_airgap_inventory(data))
        self.assertNotIn("registry", result["all"]["children"])

    def test_ssh_key_in_vars(self):
        data = load_fixture("rke2_ha_airgap.json")
        result = yaml.safe_load(generate_airgap_inventory(data))
        self.assertEqual(result["all"]["vars"]["ssh_private_key_file"], "~/.ssh/id_rsa")


class TestWriteManifest(unittest.TestCase):
    def test_manifest_contains_checksum_and_timestamp(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = os.path.join(tmpdir, "input.json")
            inventory_path = os.path.join(tmpdir, "inventory.yml")
            with open(input_path, "w") as f:
                f.write('{"type": "test"}')
            with open(inventory_path, "w") as f:
                f.write("all:\n  hosts: {}\n")

            write_manifest(tmpdir, input_path, inventory_path)

            manifest_path = os.path.join(tmpdir, ".inventory-manifest.json")
            self.assertTrue(os.path.exists(manifest_path))
            with open(manifest_path) as f:
                manifest = json.load(f)

            self.assertIn("generated_at", manifest)
            self.assertIn("input_checksum", manifest)
            self.assertIn("inventory_checksum", manifest)
            self.assertEqual(len(manifest["inventory_checksum"]), 64)  # SHA256 hex

    def test_manifest_checksum_is_stable(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = os.path.join(tmpdir, "input.json")
            inventory_path = os.path.join(tmpdir, "inventory.yml")
            content = "all:\n  hosts: {}\n"
            with open(input_path, "w") as f:
                f.write('{"type": "test"}')
            with open(inventory_path, "w") as f:
                f.write(content)

            write_manifest(tmpdir, input_path, inventory_path)
            manifest_path = os.path.join(tmpdir, ".inventory-manifest.json")
            with open(manifest_path) as f:
                m1 = json.load(f)

            write_manifest(tmpdir, input_path, inventory_path)
            with open(manifest_path) as f:
                m2 = json.load(f)

            self.assertEqual(m1["inventory_checksum"], m2["inventory_checksum"])


if __name__ == "__main__":
    unittest.main()
