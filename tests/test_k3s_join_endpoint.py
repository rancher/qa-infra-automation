"""K3s join and kubeconfig URLs must stay valid for every API host shape.

IPv6 literals need brackets; IPv4 addresses and DNS names must render unchanged.
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
ROLE_DIR = os.path.join(REPOSITORY_ROOT, "ansible", "roles", "k3s_install")
TEMPLATE_PATH = os.path.join(ROLE_DIR, "templates", "k3s-config.yaml.j2")
TASKS_PATH = os.path.join(ROLE_DIR, "tasks", "main.yml")
KUBECONFIG_TASK = "Set kubeconfig server address (cluster-init only)"

ENDPOINTS = [
    ("ipv4 address", "10.0.0.10", "10.0.0.10"),
    ("dns name", "k3s.example.com", "k3s.example.com"),
    ("ipv6 literal", "2600:1f1c:cdf::10", "[2600:1f1c:cdf::10]"),
    ("already bracketed ipv6", "[2600:1f1c:cdf::10]", "[2600:1f1c:cdf::10]"),
]


def _run_play(tmpdir, play_vars, tasks):
    play = [{"hosts": "localhost", "connection": "local", "gather_facts": False, "vars": play_vars, "tasks": tasks}]
    playbook_path = os.path.join(tmpdir, "playbook.yml")
    with open(playbook_path, "w", encoding="utf-8") as handle:
        yaml.safe_dump(play, handle)
    result = subprocess.run(
        ["ansible-playbook", "-i", "localhost,", playbook_path],
        cwd=REPOSITORY_ROOT,
        env=dict(os.environ, ANSIBLE_STDOUT_CALLBACK="default"),
        capture_output=True,
        text=True,
        check=False,
        timeout=90,
    )
    return result


@unittest.skipIf(yaml is None, "pyyaml is required")
@unittest.skipIf(shutil.which("ansible-playbook") is None, "ansible-playbook is required")
class TestK3sJoinEndpoint(unittest.TestCase):
    def _render(self, extra_vars):
        with tempfile.TemporaryDirectory() as tmpdir:
            rendered = os.path.join(tmpdir, "config.yaml")
            task = {"ansible.builtin.template": {"src": TEMPLATE_PATH, "dest": rendered, "mode": "0644"}}
            result = _run_play(tmpdir, extra_vars, [task])
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            with open(rendered, encoding="utf-8") as handle:
                return yaml.safe_load(handle) or {}

    def test_join_url_is_valid_for_every_endpoint_shape(self):
        for node_type, roles in (("server", ["cp"]), ("agent", ["worker"])):
            for case, host, expected in ENDPOINTS:
                with self.subTest(node_type=node_type, case=case):
                    config = self._render(
                        {"k3s_node_type": node_type, "node_roles": roles, "kube_api_host": host, "k3s_token": "t"}
                    )
                    self.assertEqual(config["server"], f"https://{expected}:6443")

    def test_cluster_init_does_not_emit_a_join_url(self):
        config = self._render(
            {"k3s_node_type": "cluster-init", "node_roles": ["etcd", "cp"], "kube_api_host": "2600:1f1c:cdf::10"}
        )
        self.assertNotIn("server", config)
        self.assertTrue(config["cluster-init"])

    def test_master_kubeconfig_server_is_valid_for_every_endpoint_shape(self):
        with open(TASKS_PATH, encoding="utf-8") as handle:
            task = next(t for t in yaml.safe_load(handle) if t.get("name") == KUBECONFIG_TASK)
        for case, host, expected in ENDPOINTS:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmpdir:
                kubeconfig = os.path.join(tmpdir, "k3s.yaml")
                with open(kubeconfig, "w", encoding="utf-8") as handle:
                    handle.write("clusters:\n- cluster:\n    server: https://127.0.0.1:6443\n")
                patched = dict(task, lineinfile=dict(task["lineinfile"], path=kubeconfig))
                result = _run_play(tmpdir, {"k3s_node_type": "cluster-init", "k3s_fqdn": host}, [patched])
                self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
                with open(kubeconfig, encoding="utf-8") as handle:
                    server = yaml.safe_load(handle)["clusters"][0]["cluster"]["server"]
                self.assertEqual(server, f"https://{expected}:6443")


if __name__ == "__main__":
    unittest.main()
