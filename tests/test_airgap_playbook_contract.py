"""Contract tests for ansible/airgap (the DTF airgap flow for K3s/RKE2).

The distros-test-framework qainfra provisioner drives this playbook with a fixed
inventory/extra-vars contract; these tests pin that contract without any host.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

import yaml

REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
ANSIBLE_DIR = os.path.join(REPOSITORY_ROOT, "ansible")
PLAYBOOK = os.path.join(ANSIBLE_DIR, "airgap", "airgap-playbook.yml")
CLEANUP_PLAYBOOK = os.path.join(ANSIBLE_DIR, "airgap", "airgap-cleanup-keys.yml")
ROLES = [
    "airgap_bastion_prepare", "airgap_artifacts", "airgap_registry",
    "airgap_image_publish", "airgap_product_install", "airgap_cluster_access",
]
EXTRA_VARS = {
    "product": "k3s", "kubernetes_version": "v1.36.0+k3s1", "arch": "amd64",
    "airgap_method": "tarball", "tarball_type": "tar.zst",
    "kubeconfig_file": "/tmp/kc.yaml", "airgap_facts_file": "/tmp/facts.json",
    "ssh_private_key_file": "/tmp/k.pem", "ssh_key_name": "k",
}
INVENTORY = {
    "all": {
        "vars": {
            "ansible_user": "ubuntu", "ssh_private_key_file": "/tmp/k.pem", "ssh_key_name": "k",
            "bastion_host": "1.2.3.4", "bastion_public_dns": "ec2-1-2-3-4.compute.amazonaws.com",
            "bastion_private_ip": "10.0.0.4",
        },
        "hosts": {
            "bastion-0": {"ansible_host": "1.2.3.4"},
            "master": {"ansible_host": "10.0.0.10"},
            "worker-0": {"ansible_host": "10.0.0.11"},
        },
        "children": {
            "bastion": {"hosts": {"bastion-0": {}}},
            "master": {"hosts": {"master": {}}},
            "workers": {"hosts": {"worker-0": {}}},
        },
    }
}


def _load(path):
    with open(path, encoding="utf-8") as handle:
        return yaml.safe_load(handle)


class AirgapPlaybookStaticContractTests(unittest.TestCase):
    def setUp(self):
        self.plays = _load(PLAYBOOK)

    def test_roles_exist_with_defaults_and_tasks(self):
        for role in ROLES:
            for sub in ("defaults/main.yml", "tasks/main.yml"):
                self.assertTrue(os.path.isfile(os.path.join(ANSIBLE_DIR, "roles", role, sub)), f"{role}/{sub}")

    def test_no_play_overrides_ssh_common_args(self):
        """The inventory ProxyCommand must survive; a play-level override kills it."""
        for play in self.plays:
            self.assertNotIn("ansible_ssh_common_args", play.get("vars", {}) or {}, play.get("name"))

    def test_validation_play_runs_first_on_localhost(self):
        first = self.plays[0]
        self.assertEqual(first["hosts"], "localhost")
        names = [t["name"] for t in first["tasks"]]
        self.assertTrue(any("Assert required extra-vars" in n for n in names))
        self.assertTrue(any("hardening" in n for n in names))

    def test_install_order_master_servers_workers(self):
        hosts = [p["hosts"] for p in self.plays]
        self.assertEqual(hosts, ["localhost", "bastion", "master", "servers", "workers", "bastion",
                                 "master,servers,workers", "bastion"],
                         "install order, then revoke the ephemeral key on the nodes and delete it on the bastion")
        servers_play = self.plays[3]
        self.assertEqual(servers_play.get("serial"), 1, "servers must join one at a time")

    def test_account_pem_never_copied_to_bastion_and_ephemeral_key_revoked(self):
        text = open(PLAYBOOK, encoding="utf-8").read()
        self.assertNotIn("/tmp/{{ ssh_key_name }}.pem", text, "the account PEM must not land on the bastion")
        for play in self.plays[2:5]:
            names = [t["name"] for t in play.get("pre_tasks", [])]
            self.assertTrue(any("ephemeral key" in n for n in names), play["hosts"])
        revoke = self.plays[6]
        self.assertEqual(revoke["hosts"], "master,servers,workers")
        self.assertEqual(revoke["tasks"][0]["ansible.posix.authorized_key"]["state"], "absent")

    def test_cleanup_playbook_is_best_effort_on_every_host(self):
        """Hosts that failed mid-install are gone from the main playbook's last plays."""
        plays = _load(CLEANUP_PLAYBOOK)
        self.assertEqual([p["hosts"] for p in plays], ["master,servers,workers", "bastion"])
        for play in plays:
            self.assertTrue(play.get("ignore_unreachable"), play["hosts"])
            for task in play["tasks"]:
                self.assertIs(task.get("failed_when"), False, task["name"])
        self.assertIn("dtf-airgap-ephemeral", json.dumps(plays[0]["tasks"][0]))

    def test_cni_conflict_is_rejected_before_any_host(self):
        names = [t["name"] for t in self.plays[0]["tasks"]]
        self.assertTrue(any("CNI that differs" in n for n in names))

    def test_registry_roles_only_for_registry_methods(self):
        bastion_play = self.plays[1]
        conditional = {r["role"]: r.get("when") for r in bastion_play["roles"] if isinstance(r, dict)}
        self.assertEqual(conditional["airgap_registry"], "airgap_method != 'tarball'")
        self.assertEqual(conditional["airgap_image_publish"], "airgap_method != 'tarball'")

    def test_secrets_are_never_logged(self):
        for role in ("airgap_registry", "airgap_image_publish", "airgap_product_install", "airgap_cluster_access"):
            base = os.path.join(ANSIBLE_DIR, "roles", role, "tasks")
            for name in os.listdir(base):
                tasks = _load(os.path.join(base, name))
                self._assert_no_log_on_secret_tasks(tasks, f"{role}/tasks/{name}")

    def _assert_no_log_on_secret_tasks(self, tasks, where):
        for task in tasks:
            if "block" in task:
                self._assert_no_log_on_secret_tasks(task["block"], where)
                continue
            text = json.dumps(task)
            # Secrets by identifier: the registry password, the registered htpasswd output
            # and every variable carrying kubeconfig *content* (airgap_kubeconfig,
            # airgap_kubeconfig_raw, airgap_kubeconfig_fetched). Path-only references
            # (kubectl --kubeconfig <path>, file state=absent, mounting /auth) may log.
            secret_ids = ("registry_password", "airgap_htpasswd", "airgap_kubeconfig")
            if any(sid in text for sid in secret_ids):
                self.assertTrue(task.get("no_log"), f"{where}: task {task.get('name')!r} touches a secret without no_log")

    def test_official_installers_in_offline_mode(self):
        k3s = _load(os.path.join(ANSIBLE_DIR, "roles", "airgap_product_install", "tasks", "install_k3s.yml"))
        envs = [t.get("environment", {}) for t in k3s]
        self.assertTrue(any(e.get("INSTALL_K3S_SKIP_DOWNLOAD") == "true" for e in envs))
        rke2 = _load(os.path.join(ANSIBLE_DIR, "roles", "airgap_product_install", "tasks", "install_rke2.yml"))
        self.assertTrue(any("INSTALL_RKE2_ARTIFACT_PATH" in t.get("environment", {}) for t in rke2))
        for tasks in (k3s, rke2):
            for task in tasks:
                for key in ("ansible.builtin.command", "ansible.builtin.shell"):
                    if key in task:
                        self.assertIn("argv", task[key], "installers must be invoked with argv, not a shell string")

    def test_artifacts_defaults_encode_prime_and_cache_key(self):
        defaults = _load(os.path.join(ANSIBLE_DIR, "roles", "airgap_artifacts", "defaults", "main.yml"))
        self.assertIn("image_registry_url", defaults["airgap_origin"])
        self.assertIn("'/' ~ product ~ '/'", defaults["airgap_release_url"], "Prime layout is <base>/<product>/<version>")
        for part in ("product", "kubernetes_version", "arch", "airgap_origin", "airgap_image_variant", "airgap_cni_key"):
            self.assertIn(part, defaults["airgap_artifact_key"], part)

    def test_trust_store_per_distribution(self):
        trust = _load(os.path.join(ANSIBLE_DIR, "roles", "airgap_product_install", "tasks", "trust_ca.yml"))
        families = {t["when"].split("==")[-1].strip().strip("'") for t in trust}
        self.assertEqual(families, {"Debian", "Suse", "RedHat"})


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook not available")
class AirgapPlaybookSyntaxTests(unittest.TestCase):
    def test_syntax_check_every_product_and_method(self):
        with tempfile.TemporaryDirectory() as tmp:
            inv = os.path.join(tmp, "inventory.yml")
            with open(inv, "w", encoding="utf-8") as handle:
                yaml.safe_dump(INVENTORY, handle)
            for product in ("k3s", "rke2"):
                for method in ("tarball", "private_registry", "system_default_registry"):
                    with self.subTest(product=product, method=method):
                        extra = dict(EXTRA_VARS, product=product,
                                     kubernetes_version=f"v1.36.0+{product}1",
                                     airgap_method=method, registry_username="u", registry_password="p")
                        cmd = ["ansible-playbook", "--syntax-check", "-i", inv, PLAYBOOK, CLEANUP_PLAYBOOK]
                        for key, value in extra.items():
                            cmd += ["-e", f"{key}={value}"]
                        env = dict(os.environ, ANSIBLE_CONFIG=os.path.join(ANSIBLE_DIR, "airgap", "ansible.cfg"))
                        result = subprocess.run(cmd, capture_output=True, text=True, env=env, check=False)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
