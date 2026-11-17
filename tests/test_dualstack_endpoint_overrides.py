import json
import os
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = os.path.join(os.path.dirname(__file__), "..", "ansible", "rke2")
INVENTORY = {"all": {"vars": {"kube_api_host": "inventory.example", "fqdn": "inv.example"},
    "children": {"master": {"hosts": {"master": {"ansible_connection": "local", "ansible_host": "2001:db8::1", "ansible_host_ipv6": "2001:db8::1", "node_roles": ["etcd", "cp"]}}}}}}


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook not installed")
class TestEndpointOverrides(unittest.TestCase):
    def _run(self, playbook, env):
        """Run only the localhost resolution play and return its facts."""
        with open(os.path.join(ROOT, playbook)) as f:
            plays = yaml.safe_load(f)
        play = plays[0]
        with tempfile.TemporaryDirectory() as tmp:
            dest = os.path.join(tmp, "out.json")
            play["tasks"].append({"ansible.builtin.copy": {"dest": dest, "content": json.dumps(
                {"k": "{{ kube_api_host }}", "f": "{{ fqdn }}", "c": "{{ kubeconfig_api_host }}"})}})
            with open(os.path.join(tmp, "pb.yml"), "w") as f:
                yaml.safe_dump([play], f)
            with open(os.path.join(tmp, "vars.yaml"), "w") as f:
                f.write("kubernetes_version: v1.30.0\n")
            with open(os.path.join(tmp, "inv.yml"), "w") as f:
                yaml.safe_dump(INVENTORY, f)
            out = subprocess.run(["ansible-playbook", "-i", os.path.join(tmp, "inv.yml"), os.path.join(tmp, "pb.yml")],
                                 capture_output=True, text=True, env={**os.environ, **env}, timeout=120)
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            with open(dest) as f:
                return json.load(f)

    def test_env_overrides_reach_localhost_facts_for_both_envs(self):
        env = {"KUBE_API_HOST": "lb.example", "FQDN": "cluster.example"}
        for pb in ("dualstack/rke2-playbook-dualstack.yml", "ipv6/rke2-playbook-ipv6.yml"):
            got = self._run(pb, env)
            self.assertEqual((got["k"], got["f"], got["c"]), ("lb.example", "cluster.example", "lb.example"), pb)

    def test_node_plays_take_localhost_facts_unconditionally(self):
        for pb in ("dualstack/rke2-playbook-dualstack.yml", "ipv6/rke2-playbook-ipv6.yml"):
            with open(os.path.join(ROOT, pb)) as f:
                node_play = yaml.safe_load(f)[1]
            names = [t.get("name", "") for t in node_play["pre_tasks"]]
            task = node_play["pre_tasks"][names.index(next(n for n in names if n.startswith("Use the endpoints")))]
            self.assertNotIn("when", task, pb)


if __name__ == "__main__":
    unittest.main()
