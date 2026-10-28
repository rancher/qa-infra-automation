"""The saved kubeconfig must point at a node that actually serves the API.

In a split-role topology the `servers` group holds etcd-only nodes alongside cp
nodes, in node order. RKE2 binds :6443 to localhost on a node that does not run
the apiserver, so a kubeconfig aimed at an etcd-only node is refused.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

try:
    import yaml
except ImportError:  # pragma: no cover - pyyaml ships with ansible
    yaml = None


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
ROLE_TASKS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "rke2_cluster", "tasks", "main.yml"
)

# etcd nodes deliberately precede cp nodes, which is what breaks a naive [0] pick.
SPLIT_ROLE_INVENTORY = """
all:
  hosts:
    master-node:
      ansible_host: 10.0.0.10
      node_roles: ['etcd']
    etcd-1:
      ansible_host: 10.0.0.11
      node_roles: ['etcd']
    etcd-2:
      ansible_host: 10.0.0.12
      node_roles: ['etcd']
    cp-0:
      ansible_host: 10.0.0.20
      node_roles: ['cp']
    cp-1:
      ansible_host: 10.0.0.21
      node_roles: ['cp']
  children:
    master:
      hosts:
        master-node:
    servers:
      hosts:
        etcd-1:
        etcd-2:
        cp-0:
        cp-1:
"""

# No node_roles anywhere: BYO inventories must keep the original behaviour.
BYO_INVENTORY = """
all:
  hosts:
    master-node:
      ansible_host: 10.0.0.10
    server-1:
      ansible_host: 10.0.0.11
  children:
    master:
      hosts:
        master-node:
    servers:
      hosts:
        server-1:
"""


def _kubeconfig_block():
    """The 'Fetch kubeconfig from master' block from the rke2_cluster role."""
    with open(ROLE_TASKS_PATH, encoding="utf-8") as handle:
        tasks = yaml.safe_load(handle)
    for task in tasks:
        if task.get("name") == "Fetch kubeconfig from master":
            return task
    raise AssertionError("'Fetch kubeconfig from master' block not found")


def _named_tasks(block):
    return {task.get("name"): task for task in block["block"]}


@unittest.skipIf(yaml is None, "pyyaml is required")
@unittest.skipIf(shutil.which("ansible-playbook") is None, "ansible-playbook is required")
class TestKubeconfigEndpointSelection(unittest.TestCase):
    """Render the role's own expressions, so this tests the real selection."""

    def _run(self, probe_tasks, inventory_yaml):
        block = _kubeconfig_block()
        play = [
            {
                "hosts": "all",
                "gather_facts": False,
                "connection": "local",
                "vars": block.get("vars", {}),
                "run_once": True,
                "tasks": probe_tasks,
            }
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            inventory_path = os.path.join(tmpdir, "inventory.yml")
            playbook_path = os.path.join(tmpdir, "playbook.yml")
            with open(inventory_path, "w", encoding="utf-8") as handle:
                handle.write(inventory_yaml)
            with open(playbook_path, "w", encoding="utf-8") as handle:
                yaml.safe_dump(play, handle)

            result = subprocess.run(
                ["ansible-playbook", "-i", inventory_path, playbook_path],
                cwd=REPOSITORY_ROOT,
                env=dict(os.environ, ANSIBLE_STDOUT_CALLBACK="default"),
                capture_output=True,
                text=True,
                check=False,
                timeout=90,
            )

        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        for line in result.stdout.splitlines():
            if "VALUE=" in line:
                return line.split("VALUE=", 1)[1].strip().strip('",')
        raise AssertionError(f"no VALUE= in output:\n{result.stdout}")

    def _fetch_address(self, inventory_yaml):
        """Address of the host the role delegates the kubeconfig fetch to."""
        delegate_to = _named_tasks(_kubeconfig_block())[
            "Retrieve kubeconfig from master"
        ]["delegate_to"]
        return self._run(
            [
                {"ansible.builtin.set_fact": {"_probe_host": delegate_to}},
                {
                    "ansible.builtin.debug": {
                        "msg": "VALUE={{ hostvars[_probe_host]['ansible_host'] }}"
                    }
                },
            ],
            inventory_yaml,
        )

    def _rewrite_address(self, inventory_yaml):
        """Address the role writes into the kubeconfig server URL."""
        replace = _named_tasks(_kubeconfig_block())[
            "Replace localhost with master IP in kubeconfig"
        ]["ansible.builtin.replace"]["replace"]
        return self._run(
            [{"ansible.builtin.debug": {"msg": "VALUE=" + replace}}], inventory_yaml
        )

    def test_split_role_kubeconfig_targets_a_cp_node(self):
        # A naive (servers + master)[0] picks etcd-1 (10.0.0.11), whose :6443 is
        # bound to localhost, so kubectl gets "connection refused".
        self.assertEqual(
            self._rewrite_address(SPLIT_ROLE_INVENTORY),
            "10.0.0.20",
            "kubeconfig must point at a cp node, not an etcd-only node",
        )

    def test_split_role_fetches_from_the_same_node_it_points_at(self):
        self.assertEqual(
            self._fetch_address(SPLIT_ROLE_INVENTORY),
            self._rewrite_address(SPLIT_ROLE_INVENTORY),
        )

    def test_inventory_without_node_roles_falls_back_to_first_server(self):
        self.assertEqual(self._rewrite_address(BYO_INVENTORY), "10.0.0.11")
        self.assertEqual(self._fetch_address(BYO_INVENTORY), "10.0.0.11")
