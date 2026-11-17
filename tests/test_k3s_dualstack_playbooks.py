"""Contract tests for the k3s dualstack/ipv6 playbooks and their example vars."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

try:
    import yaml
except ImportError:  # pragma: no cover - pyyaml ships with ansible
    yaml = None


REPOSITORY_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
K3S_DIR = os.path.join(REPOSITORY_ROOT, "ansible", "k3s")
ROLES_DIR = os.path.join(REPOSITORY_ROOT, "ansible", "roles")
TEMPLATE_PATH = os.path.join(ROLES_DIR, "k3s_install", "templates", "k3s-config.yaml.j2")

PLAYBOOKS = {
    "dualstack": os.path.join(K3S_DIR, "dualstack", "k3s-playbook-dualstack.yml"),
    "ipv6": os.path.join(K3S_DIR, "ipv6", "k3s-playbook-ipv6.yml"),
}


def _inventory(kube_api_host):
    # etcd-only master so the apiserver host must come from the cp node.
    return {
        "all": {
            "vars": {"kube_api_host": kube_api_host, "fqdn": "", "ansible_user": "ubuntu"},
            "hosts": {
                "master-0": {"ansible_host": "203.0.113.10", "ansible_host_ipv6": "2001:db8::10", "node_roles": ["etcd"]},
                "cp-0": {"ansible_host": "203.0.113.11", "ansible_host_ipv6": "2001:db8::11", "node_roles": ["cp"]},
            },
            "children": {"master": {"hosts": {"master-0": {}}}, "servers": {"hosts": {"cp-0": {}}}},
        }
    }


def _run(args, tmpdir, env=None):
    return subprocess.run(
        ["ansible-playbook", *args],
        cwd=tmpdir,
        env=dict(os.environ, ANSIBLE_ROLES_PATH=ROLES_DIR, **(env or {})),
        capture_output=True,
        text=True,
        check=False,
        timeout=120,
    )


@unittest.skipIf(yaml is None, "pyyaml is required")
@unittest.skipIf(shutil.which("ansible-playbook") is None, "ansible-playbook is required")
class TestEndpointResolution(unittest.TestCase):
    def _localhost_facts(self, env_name, kube_api_host, env=None):
        """Run only the first (localhost) play and return the facts it set."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with open(PLAYBOOKS[env_name], encoding="utf-8") as handle:
                first_play = yaml.safe_load(handle)[:1]
            self.assertEqual(first_play[0]["hosts"], "localhost")
            with open(os.path.join(tmpdir, "playbook.yml"), "w", encoding="utf-8") as handle:
                yaml.safe_dump(first_play, handle)
            with open(os.path.join(tmpdir, "vars.yaml"), "w", encoding="utf-8") as handle:
                yaml.safe_dump({"kubernetes_version": "v1.34.2+k3s1"}, handle)
            with open(os.path.join(tmpdir, "inventory.yml"), "w", encoding="utf-8") as handle:
                yaml.safe_dump(_inventory(kube_api_host), handle)
            result = _run(
                ["-i", "inventory.yml", "playbook.yml"],
                tmpdir,
                env=dict(ANSIBLE_STDOUT_CALLBACK="json", **(env or {})),
            )
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        facts = {}
        for play in json.loads(result.stdout)["plays"]:
            for task in play["tasks"]:
                facts.update(task["hosts"].get("localhost", {}).get("ansible_facts", {}))
        return facts

    def test_dualstack_defaults_to_master_and_cp_ipv4(self):
        facts = self._localhost_facts("dualstack", "")
        self.assertEqual(facts["kube_api_host"], "203.0.113.10")
        self.assertEqual(facts["apiserver_inventory_host"], "cp-0")
        self.assertEqual(facts["kube_api_apiserver_host"], "203.0.113.11")

    def test_dualstack_keeps_inventory_kube_api_host(self):
        facts = self._localhost_facts("dualstack", "2001:db8::10")
        self.assertEqual(facts["kube_api_host"], "2001:db8::10")

    def test_ipv6_replaces_an_ipv4_kube_api_host_with_master_ipv6(self):
        facts = self._localhost_facts("ipv6", "203.0.113.10")
        self.assertEqual(facts["kube_api_host"], "2001:db8::10")
        self.assertEqual(facts["kube_api_apiserver_host"], "2001:db8::11")

    def test_kube_api_host_env_override_wins(self):
        facts = self._localhost_facts("ipv6", "", env={"KUBE_API_HOST": "2001:db8::99"})
        self.assertEqual(facts["kube_api_host"], "2001:db8::99")

    def test_dualstack_kubeconfig_uses_cp_ipv4_not_fqdn(self):
        # IPv6-first runs publish an AAAA-only fqdn that IPv4-only controllers cannot dial.
        import jinja2

        with open(PLAYBOOKS["dualstack"], encoding="utf-8") as handle:
            plays = yaml.safe_load(handle)
        task = next(
            t for play in plays for t in play.get("tasks", [])
            if t.get("name") == "Update kubeconfig server address"
        )
        host = jinja2.Environment().from_string(task["vars"]["_host"]).render(
            fqdn="api.example.test",
            hostvars={"localhost": {"kube_api_apiserver_host": "203.0.113.11"}},
        )
        self.assertEqual(host, "203.0.113.11")

    def test_playbooks_pass_syntax_check(self):
        for name, playbook in PLAYBOOKS.items():
            with self.subTest(env=name), tempfile.TemporaryDirectory() as tmpdir:
                result = _run(["--syntax-check", "-i", "localhost,", playbook], tmpdir)
                self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)


@unittest.skipIf(yaml is None, "pyyaml is required")
@unittest.skipIf(shutil.which("ansible-playbook") is None, "ansible-playbook is required")
class TestExampleFlagsRender(unittest.TestCase):
    """Each example must render a k3s config with the intended IP family order."""

    CASES = [
        ("dualstack/examples/vars.dualstack.yaml", "10.0.0.10,2001:db8::10", "10.42.0.0/16,2001:cafe:42::/56"),
        ("dualstack/examples/vars.dualstack.ipv6.yaml", "2001:db8::10,10.0.0.10", "2001:cafe:42::/56,10.42.0.0/16"),
        ("ipv6/examples/vars.ipv6.yaml", "2001:db8::10", "2001:cafe:42::/56"),
    ]

    def _render(self, vars_file, node_type, roles):
        with tempfile.TemporaryDirectory() as tmpdir:
            rendered = os.path.join(tmpdir, "config.yaml")
            play = [{
                "hosts": "localhost",
                "connection": "local",
                "gather_facts": False,
                "vars_files": [os.path.join(K3S_DIR, vars_file)],
                "vars": {"k3s_node_type": node_type, "node_roles": roles, "kube_api_host": "2001:db8::10",
                         "ansible_host_ipv6": "2001:db8::10", "k3s_token": "t"},
                "tasks": [{"ansible.builtin.template": {"src": TEMPLATE_PATH, "dest": rendered, "mode": "0644"}}],
            }]
            with open(os.path.join(tmpdir, "play.yml"), "w", encoding="utf-8") as handle:
                yaml.safe_dump(play, handle)
            facts = json.dumps({"ansible_facts": {"default_ipv4": {"address": "10.0.0.10"}}})
            result = _run(["-i", "localhost,", "play.yml", "-e", facts], tmpdir)
            self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
            with open(rendered, encoding="utf-8") as handle:
                return yaml.safe_load(handle)

    def test_examples_render_node_ip_and_cidrs(self):
        for vars_file, node_ip, cluster_cidr in self.CASES:
            with self.subTest(vars_file=vars_file):
                server = self._render(vars_file, "cluster-init", ["etcd", "cp"])
                self.assertEqual(server["node-ip"], node_ip)
                self.assertEqual(server["cluster-cidr"], cluster_cidr)
                agent = self._render(vars_file, "agent", ["worker"])
                self.assertEqual(agent["node-ip"], node_ip)
                self.assertEqual(agent["server"], "https://[2001:db8::10]:6443")
                self.assertNotIn("cluster-cidr", agent)

    def test_vars_yaml_examples_match_a_scenario(self):
        for env_name, example in (("dualstack", "vars.dualstack.yaml"), ("ipv6", "vars.ipv6.yaml")):
            with self.subTest(env=env_name):
                with open(os.path.join(K3S_DIR, env_name, "vars.yaml.example"), encoding="utf-8") as a, \
                        open(os.path.join(K3S_DIR, env_name, "examples", example), encoding="utf-8") as b:
                    self.assertEqual(a.read(), b.read())


if __name__ == "__main__":
    unittest.main()
