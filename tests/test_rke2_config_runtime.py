"""Real Ansible roles/handlers with only the system-service boundary substituted."""

import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

import yaml


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
ROLE_PATH = REPOSITORY_ROOT / "ansible/roles/rke2_config"
FIXTURE_LIBRARY = REPOSITORY_ROOT / "tests/fixtures/rke2_config/library"


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
@unittest.skipIf(
    sys.platform == "darwin" and os.environ.get("QA_RUN_ANSIBLE_RUNTIME_TESTS") != "1",
    "local Ansible execution requires running outside the macOS sandbox",
)
class TestRKE2ConfigRuntime(unittest.TestCase):
    def _exercise(self, *, node_role="master", installed=True, variables=None,
                  fail_restart=False, stale_unit=False, service_state="running"):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            config_dir = root / "config"
            config_dir.mkdir()
            kubeconfig = config_dir / "rke2.yaml"
            kubeconfig.write_text("dummy-kubeconfig\n", encoding="utf-8")
            kubeconfig.chmod(0o420)
            if installed:
                (config_dir / "config.yaml").write_text(
                    "cni: calico\nwrite-kubeconfig-mode: 0644\ntoken: dummy-existing-token\n",
                    encoding="utf-8",
                )
            role = root / "rke2_config"
            shutil.copytree(ROLE_PATH, role)
            service = "rke2-agent" if node_role == "agent" else "rke2-server"
            services = {}
            if installed:
                services[service + ".service"] = {
                    "name": service + ".service", "source": "systemd", "state": service_state,
                    "status": "not-found" if stale_unit else "enabled",
                }
            for relative in ("tasks/main.yml", "handlers/main.yml"):
                path = role / relative
                tasks = yaml.safe_load(path.read_text(encoding="utf-8"))
                for task in tasks:
                    task.pop("become", None)
                    for value in task.values():
                        if isinstance(value, dict):
                            value.pop("owner", None)
                            value.pop("group", None)
                    if "ansible.builtin.service_facts" in task:
                        task.pop("ansible.builtin.service_facts")
                        task["qa_rke2_service"] = {"operation": "facts", "services": services}
                    if "ansible.builtin.systemd" in task:
                        arguments = task.pop("ansible.builtin.systemd")
                        task["qa_rke2_service"] = {
                            **arguments, "operation": "restart", "fail_restart": fail_restart,
                            "config_path": str(config_dir / "config.yaml"),
                            "kubeconfig_path": str(kubeconfig), "log_path": str(root / "restarts"),
                        }
                path.write_text(yaml.safe_dump(tasks, sort_keys=False), encoding="utf-8")

            play_vars = {
                "rke2_config_dir": str(config_dir), "rke2_node_role": node_role,
                "node_roles": ["worker"] if node_role == "agent" else ["cp", "etcd"],
                "fqdn": "api.example.invalid", "kube_api_host": "192.0.2.10",
                "ansible_host": "192.0.2.10", "ansible_python_interpreter": sys.executable,
                **(variables or {}),
            }
            playbook = root / "play.yml"
            playbook.write_text(yaml.safe_dump([
                {
                    "name": "Configuration before installation",
                    "hosts": "localhost", "connection": "local", "gather_facts": False,
                    "vars": play_vars,
                    "tasks": [{"name": "Configure", "ansible.builtin.include_role": {"name": str(role)}}],
                },
                {
                    "name": "Later installation play",
                    "hosts": "localhost", "connection": "local", "gather_facts": False,
                    "tasks": [{"name": "Set installed fact", "ansible.builtin.set_fact": {"rke2_installed": True}}],
                },
            ]), encoding="utf-8")
            environment = os.environ.copy()
            environment.update({
                "ANSIBLE_LIBRARY": str(FIXTURE_LIBRARY),
                "ANSIBLE_LOCAL_TEMP": str(root / "ansible-local"),
                "ANSIBLE_REMOTE_TEMP": str(root / "ansible-remote"),
                "OBJC_DISABLE_INITIALIZE_FORK_SAFETY": "YES",
            })

            def run():
                return subprocess.run(
                    ["ansible-playbook", "-i", "localhost,", str(playbook)],
                    capture_output=True, text=True, env=environment, timeout=90, check=False,
                )

            first = run()
            first_log = (root / "restarts").read_text() if (root / "restarts").exists() else ""
            second = run() if first.returncode == 0 else None
            final_log = (root / "restarts").read_text() if (root / "restarts").exists() else ""
            return {
                "first": first, "second": second, "first_log": first_log, "final_log": final_log,
                "mode": stat.S_IMODE(kubeconfig.stat().st_mode),
                "config": yaml.safe_load((config_dir / "config.yaml").read_text()),
            }

    def test_existing_service_restarts_before_later_install_fact(self):
        result = self._exercise()
        self.assertEqual(result["first"].returncode, 0, result["first"].stdout + result["first"].stderr)
        self.assertEqual(result["mode"], 0o644)
        self.assertEqual(result["config"]["cni"], "calico")
        self.assertEqual(result["config"]["token"], "dummy-existing-token")
        self.assertEqual(json.loads(result["first_log"])["name"], "rke2-server")
        self.assertEqual(result["second"].returncode, 0, result["second"].stdout)
        self.assertRegex(result["second"].stdout, r"changed=0\s")
        self.assertEqual(result["first_log"], result["final_log"])

    def test_fresh_service_does_not_restart_before_installation(self):
        result = self._exercise(installed=False, variables={"rke2_cni": ""})
        self.assertEqual(result["first"].returncode, 0, result["first"].stdout)
        self.assertEqual(result["final_log"], "")
        self.assertNotIn("cni", result["config"])

    def test_existing_agent_preserves_join_token_and_restarts_correct_service(self):
        for node_role in ("agent", "server"):
            with self.subTest(node_role=node_role):
                result = self._exercise(node_role=node_role)
                self.assertEqual(result["first"].returncode, 0, result["first"].stdout)
                self.assertEqual(result["config"]["token"], "dummy-existing-token")
                service = "rke2-agent" if node_role == "agent" else "rke2-server"
                self.assertEqual(json.loads(result["first_log"])["name"], service)
                self.assertEqual(result["first_log"], result["final_log"])

    def test_token_from_configuration_overrides_preserved_token(self):
        for key in ("rke2_additional_config", "rke2_server_config", "rke2_agent_config"):
            with self.subTest(key=key):
                result = self._exercise(
                    node_role="agent" if key == "rke2_agent_config" else "master",
                    variables={key: {"token": "dummy-config-token"}},
                )
                self.assertEqual(result["first"].returncode, 0, result["first"].stdout)
                self.assertEqual(result["config"]["token"], "dummy-config-token")
                self.assertEqual(result["first_log"], result["final_log"])

    def test_explicit_empty_token_removes_the_previous_token(self):
        result = self._exercise(variables={"rke2_token": ""})
        self.assertEqual(result["first"].returncode, 0, result["first"].stdout)
        self.assertNotIn("token", result["config"])

    def test_explicit_token_and_mode_take_precedence(self):
        result = self._exercise(variables={
            "rke2_token": "dummy-replacement-token",
            "rke2_additional_config": {"write-kubeconfig-mode": "0600"},
        })
        self.assertEqual(result["first"].returncode, 0, result["first"].stdout)
        self.assertEqual(result["mode"], 0o600)
        self.assertEqual(result["config"]["token"], "dummy-replacement-token")

    def test_explicit_restart_opt_out_is_preserved(self):
        result = self._exercise(variables={"rke2_installed": False})
        self.assertEqual(result["first"].returncode, 0, result["first"].stdout)
        self.assertEqual(result["final_log"], "")

    def test_not_found_unit_does_not_count_as_installed(self):
        result = self._exercise(stale_unit=True)
        self.assertEqual(result["first"].returncode, 0, result["first"].stdout)
        self.assertEqual(result["final_log"], "")

    def test_stopped_service_is_left_for_cluster_start(self):
        result = self._exercise(service_state="stopped")
        self.assertEqual(result["first"].returncode, 0, result["first"].stdout)
        self.assertEqual(result["final_log"], "")

    def test_restart_failure_fails_the_configuration_play(self):
        result = self._exercise(fail_restart=True)
        self.assertNotEqual(result["first"].returncode, 0)
        self.assertIn("Simulated service restart failure", result["first"].stdout)
        self.assertNotIn("TASK [Set installed fact]", result["first"].stdout)


if __name__ == "__main__":
    unittest.main()
