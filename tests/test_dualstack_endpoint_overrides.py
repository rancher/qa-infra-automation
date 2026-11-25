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
    def _run(self, playbook, env, inventory=INVENTORY, extra=None, args=()):
        """Run only the localhost resolution play and return its facts."""
        with open(os.path.join(ROOT, playbook)) as f:
            plays = yaml.safe_load(f)
        play = plays[0]
        with tempfile.TemporaryDirectory() as tmp:
            dest = os.path.join(tmp, "out.json")
            play["tasks"].append({"ansible.builtin.copy": {"dest": dest, "content": json.dumps(
                extra or {"k": "{{ kube_api_host }}", "f": "{{ fqdn }}", "c": "{{ kubeconfig_api_host }}"})},
                "tags": ["always"]})
            with open(os.path.join(tmp, "pb.yml"), "w") as f:
                yaml.safe_dump([play], f)
            with open(os.path.join(tmp, "vars.yaml"), "w") as f:
                f.write("kubernetes_version: v1.30.0\n")
            with open(os.path.join(tmp, "inv.yml"), "w") as f:
                yaml.safe_dump(inventory, f)
            out = subprocess.run(["ansible-playbook", "-i", os.path.join(tmp, "inv.yml"), os.path.join(tmp, "pb.yml"), *args],
                                 capture_output=True, text=True, env={**os.environ, **env}, timeout=120)
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            with open(dest) as f:
                return json.load(f)

    def test_env_overrides_reach_localhost_facts_for_both_envs(self):
        env = {"KUBE_API_HOST": "lb.example", "FQDN": "cluster.example"}
        for pb in ("dualstack/rke2-playbook-dualstack.yml", "ipv6/rke2-playbook-ipv6.yml"):
            got = self._run(pb, env)
            self.assertEqual((got["k"], got["f"], got["c"]), ("lb.example", "cluster.example", "lb.example"), pb)

    def test_health_check_targets_a_cp_node_not_an_etcd_only_master(self):
        inventory = json.loads(json.dumps(INVENTORY))
        inventory["all"]["children"]["master"]["hosts"]["master"]["node_roles"] = ["etcd"]
        inventory["all"]["children"]["servers"] = {"hosts": {"cp-0": {
            "ansible_connection": "local", "ansible_host": "2001:db8::2", "ansible_host_ipv6": "2001:db8::2", "node_roles": ["cp"]}}}
        for pb in ("dualstack/rke2-playbook-dualstack.yml", "ipv6/rke2-playbook-ipv6.yml"):
            # --tags health alone must still resolve the host the health play targets.
            got = self._run(pb, {}, inventory, {"h": "{{ groups['rke2_health_check'] | join(',') }}"}, ("--tags", "health"))
            self.assertEqual(got["h"], "cp-0", pb)
            with open(os.path.join(ROOT, pb)) as f:
                health = next(p for p in yaml.safe_load(f) if p.get("name") == "Check RKE2 cluster health")
            self.assertEqual(health["hosts"], "rke2_health_check", pb)

    def test_kubeconfig_server_brackets_only_bare_ipv6(self):
        from jinja2 import Environment

        cases = {"2001:db8::1": "[2001:db8::1]", "[2001:db8::1]": "[2001:db8::1]",
                 "lb.example": "lb.example", "203.0.113.10": "203.0.113.10"}
        for pb in ("dualstack/rke2-playbook-dualstack.yml", "ipv6/rke2-playbook-ipv6.yml"):
            with open(os.path.join(ROOT, pb)) as f:
                play = next(p for p in yaml.safe_load(f) if p.get("name", "").startswith("Format local kubeconfig"))
            tmpl = Environment().from_string(play["vars"]["_kubeconfig_server"])
            for host, want in cases.items():
                self.assertEqual(tmpl.render(kubeconfig_api_host=host).strip(), want, f"{pb}: {host}")

    def test_node_plays_take_localhost_facts_unconditionally(self):
        for pb in ("dualstack/rke2-playbook-dualstack.yml", "ipv6/rke2-playbook-ipv6.yml"):
            with open(os.path.join(ROOT, pb)) as f:
                node_play = yaml.safe_load(f)[1]
            names = [t.get("name", "") for t in node_play["pre_tasks"]]
            task = node_play["pre_tasks"][names.index(next(n for n in names if n.startswith("Use the endpoints")))]
            self.assertNotIn("when", task, pb)

    def test_cluster_role_delegates_to_a_cp_node_not_an_etcd_only_server(self):
        role_vars = os.path.abspath(os.path.join(ROOT, "..", "roles", "rke2_cluster", "vars", "main.yml"))
        local = {"ansible_connection": "local"}
        cases = {  # split topology: second etcd-only node lands first in servers
            "cp-0": {"master": {"m": {**local, "node_roles": ["etcd"]}},
                     "servers": {"etcd-1": {**local, "node_roles": ["etcd"]}, "cp-0": {**local, "node_roles": ["cp"]}}},
            "s-0": {"master": {"m": {**local, "node_roles": ["etcd", "cp"]}},
                    "servers": {"s-0": {**local, "node_roles": ["etcd", "cp"]}}},
        }
        for want, children in cases.items():
            inv = {"all": {"children": {g: {"hosts": h} for g, h in children.items()}}}
            with tempfile.TemporaryDirectory() as tmp:
                dest = os.path.join(tmp, "out.txt")
                pb = [{"hosts": "localhost", "gather_facts": False, "vars_files": [role_vars],
                       "tasks": [{"ansible.builtin.copy": {"dest": dest, "content": "{{ rke2_cluster_api_host }}"}}]}]
                with open(os.path.join(tmp, "pb.yml"), "w") as f:
                    yaml.safe_dump(pb, f)
                with open(os.path.join(tmp, "inv.yml"), "w") as f:
                    yaml.safe_dump(inv, f)
                out = subprocess.run(["ansible-playbook", "-i", os.path.join(tmp, "inv.yml"), os.path.join(tmp, "pb.yml")],
                                     capture_output=True, text=True, timeout=120)
                self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
                with open(dest) as f:
                    self.assertEqual(f.read().strip(), want)
        with open(os.path.join(ROOT, "..", "roles", "rke2_cluster", "tasks", "main.yml")) as f:
            self.assertNotIn("groups['master'])[0]", f.read())

    def test_kubeconfig_is_fetched_where_later_plays_read_it(self):
        for pb in ("dualstack/rke2-playbook-dualstack.yml", "ipv6/rke2-playbook-ipv6.yml"):
            with open(os.path.join(ROOT, pb)) as f:
                plays = yaml.safe_load(f)
            role = next(r for p in plays for r in p.get("roles", []) if isinstance(r, dict) and r.get("role") == "rke2_cluster")
            fmt = next(p for p in plays if p.get("name", "").startswith("Format local kubeconfig"))
            self.assertEqual(role["vars"]["rke2_kubeconfig_dest"], fmt["tasks"][0]["ansible.builtin.replace"]["path"], pb)

    def test_ipv6_vars_example_uses_ipv6_node_ip(self):
        with open(os.path.join(ROOT, "ipv6", "vars.yaml.example")) as f:
            example = yaml.safe_load(f)
        for key in ("server_flags", "worker_flags"):
            flags = yaml.safe_load(example[key])
            self.assertEqual(flags["node-ip"], "{{ ansible_host_ipv6 }}", key)
            self.assertNotIn("0.0.0.0", example[key], key)


if __name__ == "__main__":
    unittest.main()
