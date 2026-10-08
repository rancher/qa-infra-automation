"""The rendered join URL must stay valid for every kube_api_host shape.

IPv6 literals need brackets in a URL. IPv4 addresses, DNS names and load
balancer hostnames must render exactly as they did before IPv6 support, because
default/proxy/airgap point kube_api_host at an LB rather than at a node.
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
ROLE_DEFAULTS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "rke2_config", "defaults", "main.yml"
)
TEMPLATE_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "rke2_config", "templates", "config.yaml.j2"
)

# kube_api_host -> expected authority in the rendered server URL
ENDPOINTS = [
    ("ipv4 address", "10.0.0.10", "10.0.0.10"),
    ("dns name", "rke2.example.com", "rke2.example.com"),
    (
        "load balancer hostname",
        "my-nlb-123.elb.us-west-1.amazonaws.com",
        "my-nlb-123.elb.us-west-1.amazonaws.com",
    ),
    ("ipv6 literal", "2600:1f1c:cdf::10", "[2600:1f1c:cdf::10]"),
    ("already bracketed ipv6", "[2600:1f1c:cdf::10]", "[2600:1f1c:cdf::10]"),
]

SERVER_NODE = {"rke2_node_role": "server", "node_roles": ["cp"]}
AGENT_NODE = {"rke2_node_role": "agent", "node_roles": ["worker"]}

# A master group whose address differs from kube_api_host, so that preferring
# the master node over kube_api_host is detectable.
INVENTORY_WITH_MASTER = """
all:
  hosts:
    master-node:
      ansible_host: 10.0.0.10
    cp-0:
      ansible_host: 10.0.0.20
  children:
    master:
      hosts:
        master-node:
"""


def _role_defaults():
    with open(ROLE_DEFAULTS_PATH, encoding="utf-8") as handle:
        return yaml.safe_load(handle)


@unittest.skipIf(yaml is None, "pyyaml is required")
@unittest.skipIf(shutil.which("ansible-playbook") is None, "ansible-playbook is required")
class TestJoinEndpointRendering(unittest.TestCase):
    def _render(self, extra_vars, inventory_yaml=None, target="localhost"):
        """Render the real role template and parse it as the YAML RKE2 reads."""
        play_vars = {
            "rke2_server_config": {},
            "rke2_agent_config": _role_defaults()["rke2_agent_config"],
            "rke2_disable_components": [],
        }
        play_vars.update(extra_vars)

        with tempfile.TemporaryDirectory() as tmpdir:
            rendered_path = os.path.join(tmpdir, "config.yaml")
            play = [
                {
                    "hosts": target,
                    "connection": "local",
                    "gather_facts": False,
                    "vars": play_vars,
                    "tasks": [
                        {
                            "ansible.builtin.template": {
                                "src": TEMPLATE_PATH,
                                "dest": rendered_path,
                                "mode": "0644",
                            }
                        }
                    ],
                }
            ]
            playbook_path = os.path.join(tmpdir, "playbook.yml")
            with open(playbook_path, "w", encoding="utf-8") as handle:
                yaml.safe_dump(play, handle)

            if inventory_yaml is None:
                inventory_arg = "localhost,"
            else:
                inventory_arg = os.path.join(tmpdir, "inventory.yml")
                with open(inventory_arg, "w", encoding="utf-8") as handle:
                    handle.write(inventory_yaml)

            result = subprocess.run(
                ["ansible-playbook", "-i", inventory_arg, playbook_path],
                cwd=REPOSITORY_ROOT,
                env=dict(os.environ, ANSIBLE_STDOUT_CALLBACK="default"),
                capture_output=True,
                text=True,
                check=False,
                timeout=90,
            )
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            with open(rendered_path, encoding="utf-8") as handle:
                text = handle.read()

        return text, yaml.safe_load(text) or {}

    def test_server_join_url_is_valid_for_every_endpoint_shape(self):
        for case, host, expected in ENDPOINTS:
            with self.subTest(case=case):
                _, config = self._render({"kube_api_host": host, **SERVER_NODE})
                self.assertEqual(config["server"], f"https://{expected}:9345")

    def test_agent_join_url_is_valid_for_every_endpoint_shape(self):
        for case, host, expected in ENDPOINTS:
            with self.subTest(case=case):
                _, config = self._render({"kube_api_host": host, **AGENT_NODE})
                self.assertEqual(config["server"], f"https://{expected}:9345")

    def test_join_url_follows_kube_api_host_not_the_master_node(self):
        """default/proxy/airgap point kube_api_host at an LB; joins must use it.

        Rendered on cp-0 with a populated master group, so resolving the join
        host from groups['master'][0] would surface as 10.0.0.10.
        """
        _, config = self._render(
            {"kube_api_host": "lb.example.com", **SERVER_NODE},
            inventory_yaml=INVENTORY_WITH_MASTER,
            target="cp-0",
        )
        self.assertEqual(config["server"], "https://lb.example.com:9345")

    def test_agent_join_url_follows_kube_api_host_not_the_master_node(self):
        _, config = self._render(
            {"kube_api_host": "lb.example.com", **AGENT_NODE},
            inventory_yaml=INVENTORY_WITH_MASTER,
            target="cp-0",
        )
        self.assertEqual(config["server"], "https://lb.example.com:9345")

    def test_rke2_join_host_overrides_kube_api_host(self):
        _, config = self._render(
            {
                "kube_api_host": "lb.example.com",
                "rke2_join_host": "10.0.0.99",
                **SERVER_NODE,
            }
        )
        self.assertEqual(config["server"], "https://10.0.0.99:9345")

    def test_master_does_not_emit_a_join_url(self):
        _, config = self._render(
            {
                "kube_api_host": "10.0.0.10",
                "rke2_node_role": "master",
                "node_roles": ["etcd"],
            }
        )
        self.assertNotIn("server", config)

    def test_agent_emits_exactly_one_server_key(self):
        text, _ = self._render({"kube_api_host": "2600:1f1c:cdf::10", **AGENT_NODE})
        server_lines = [line for line in text.splitlines() if line.startswith("server:")]
        self.assertEqual(len(server_lines), 1, text)
