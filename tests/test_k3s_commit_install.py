"""Contract tests for installing K3s from a commit hash."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
ROLE_PATH = os.path.join(REPOSITORY_ROOT, "ansible", "roles", "k3s_install")


def _load(*parts):
    with open(os.path.join(ROLE_PATH, *parts), encoding="utf-8") as yaml_file:
        return yaml.safe_load(yaml_file)


def _commit_block_tasks():
    block = next(
        task for task in _load("tasks", "main.yml")
        if task.get("name") == "Install K3s from commit hash via install script"
    )
    return block["block"]


class K3sCommitInstallTest(unittest.TestCase):
    """get.k3s.io refuses commit builds without jq, unzip and GITHUB_TOKEN."""

    def test_tools_are_installed_before_the_script_runs(self):
        names = [task["name"] for task in _commit_block_tasks()]
        tools = next(
            task for task in _commit_block_tasks()
            if task["name"] == "Install the tools the commit install script needs"
        )

        self.assertEqual(tools["ansible.builtin.package"]["name"], ["jq", "unzip"])
        self.assertLess(
            names.index("Install the tools the commit install script needs"),
            names.index("Install K3s via install script"),
        )

    def test_the_script_gets_the_token(self):
        install = next(
            task for task in _commit_block_tasks()
            if task["name"] == "Install K3s via install script"
        )

        self.assertNotIn("environment", install)
        self.assertEqual(install["args"]["stdin"], "{{ k3s_github_token }}")
        self.assertTrue(install["no_log"])
        self.assertEqual(
            _load("defaults", "main.yml")["k3s_github_token"],
            "{{ lookup('env', 'GITHUB_TOKEN') }}",
        )

    def test_a_missing_token_fails_before_commit_prerequisites_are_installed(self):
        tasks = _commit_block_tasks()
        names = [task["name"] for task in tasks]
        check = tasks[names.index("Require a GitHub token for commit installs")]

        self.assertIn("k3s_github_token | length > 0", check["ansible.builtin.assert"]["that"])
        self.assertNotIn("k3s_github_token", check["ansible.builtin.assert"]["fail_msg"].replace(
            "or k3s_github_token.", ""))
        self.assertLess(
            names.index("Require a GitHub token for commit installs"),
            names.index("Install the tools the commit install script needs"),
        )


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
@unittest.skipIf(
    sys.platform == "darwin" and os.environ.get("QA_RUN_ANSIBLE_RUNTIME_TESTS") != "1",
    "local Ansible execution requires running outside the macOS sandbox",
)
class K3sCommitInstallRuntimeTest(unittest.TestCase):
    def _run(self, root, tasks, token="", variables=None):
        playbook = root / "play.yml"
        playbook.write_text(yaml.safe_dump([{
            "hosts": "localhost", "connection": "local", "gather_facts": False,
            "vars": {
                "k3s_github_token": _load("defaults", "main.yml")["k3s_github_token"],
                "kubernetes_version": "0123456789abcdef", "k3s_node_type": "agent",
                "ansible_user": "root", "ansible_python_interpreter": sys.executable,
                **(variables or {}),
            },
            # Remote commands must not inherit the controller's token by accident.
            "environment": {"GITHUB_TOKEN": ""}, "tasks": tasks,
        }]), encoding="utf-8")
        config = root / "ansible.cfg"
        config.write_text("[defaults]\n", encoding="utf-8")
        environment = {
            **os.environ, "GITHUB_TOKEN": token, "ANSIBLE_CONFIG": str(config),
            "ANSIBLE_LOG_PATH": str(root / "ansible.log"),
            "ANSIBLE_LOCAL_TEMP": str(root / "local"),
            "ANSIBLE_REMOTE_TEMP": str(root / "remote"),
            "OBJC_DISABLE_INITIALIZE_FORK_SAFETY": "YES",
        }
        result = subprocess.run(
            ["ansible-playbook", "-vvv", "-i", "localhost,", str(playbook)],
            env=environment, capture_output=True, text=True, timeout=60, check=False,
        )
        output = result.stdout + result.stderr + (root / "ansible.log").read_text(encoding="utf-8")
        return result.returncode, output

    def test_token_reaches_installer_without_leaking_on_success_or_failure(self):
        for exit_code in (0, 1):
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                token = "dummy-secret-for-commit-install"
                installer = root / "installer.sh"
                installer.write_text(
                    f'test "$GITHUB_TOKEN" = "{token}" || exit 91\n'
                    'test "$INSTALL_K3S_COMMIT" = "0123456789abcdef" || exit 92\n'
                    'test "$INSTALL_K3S_EXEC" = "agent" || exit 93\n'
                    'test "$INSTALL_K3S_SKIP_START" = "true" || exit 94\n'
                    f'touch "{root / "installed"}"\n'
                    'printf "%s\\n" "$GITHUB_TOKEN"\n'
                    f"exit {exit_code}\n", encoding="utf-8",
                )
                task = next(t for t in _commit_block_tasks() if t["name"] == "Install K3s via install script")
                task["ansible.builtin.shell"] = task["ansible.builtin.shell"].replace(
                    "/tmp/k3s-install.sh", str(installer),
                )
                task.update(retries=0, delay=0)

                rc, output = self._run(root, [task], token=token)

                self.assertEqual(rc == 0, exit_code == 0, output)
                self.assertTrue((root / "installed").exists(), output)
                self.assertNotIn(token, output)

    def test_missing_token_stops_before_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            check = next(t for t in _commit_block_tasks() if t["name"] == "Require a GitHub token for commit installs")
            marker = {"ansible.builtin.file": {"path": str(root / "installed"), "state": "touch"}}

            rc, output = self._run(root, [check, marker])

            self.assertNotEqual(rc, 0, output)
            self.assertIn("needs GITHUB_TOKEN", output)
            self.assertFalse((root / "installed").exists())

    def test_transactional_tools_are_activated_before_the_installer(self):
        for transactional, already_present in ((False, False), (True, False), (True, True)):
            with self.subTest(transactional=transactional, already_present=already_present):
                with tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    active = root / "bin"
                    pending = root / "pending"
                    active.mkdir()
                    pending.mkdir()
                    transactional_path = root / "transactional-update"
                    if transactional:
                        transactional_path.touch()
                    if already_present:
                        for name in ("jq", "unzip"):
                            (active / name).write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                            (active / name).chmod(0o755)

                    tasks = []
                    for task in _commit_block_tasks():
                        if "ansible.builtin.stat" in task:
                            task["ansible.builtin.stat"]["path"] = str(transactional_path)
                        elif "ansible.builtin.package" in task:
                            packages = task.pop("ansible.builtin.package")["name"]
                            target = pending if transactional and not already_present else active
                            task["ansible.builtin.command"] = {"argv": [
                                sys.executable, "-c",
                                "from pathlib import Path; import sys; "
                                "[(p.write_text('#!/bin/sh\\nexit 0\\n'), p.chmod(0o755)) "
                                "for p in (Path(sys.argv[1]) / n for n in sys.argv[2:])]",
                                str(target), *packages,
                            ]}
                        elif "ansible.builtin.command" in task:
                            task["environment"] = {"PATH": str(active)}
                        elif "ansible.builtin.reboot" in task:
                            task.pop("ansible.builtin.reboot")
                            task["ansible.builtin.command"] = {"argv": [
                                sys.executable, "-c",
                                "from pathlib import Path; import sys; "
                                "[p.replace(Path(sys.argv[2]) / p.name) for p in Path(sys.argv[1]).iterdir()]; "
                                "Path(sys.argv[3]).touch()",
                                str(pending), str(active), str(root / "rebooted"),
                            ]}
                        else:
                            continue
                        tasks.append(task)
                    tasks.append({
                        "name": "Installer requires both tools",
                        "ansible.builtin.command": {"argv": [
                            "/bin/sh", "-c", "command -v jq && command -v unzip",
                        ]}, "environment": {"PATH": str(active)},
                    })

                    rc, output = self._run(root, tasks)

                    self.assertEqual(rc, 0, output)
                    self.assertEqual((root / "rebooted").exists(), transactional and not already_present)
                    (root / "rebooted").unlink(missing_ok=True)
                    rc, output = self._run(root, tasks)
                    self.assertEqual(rc, 0, output)
                    self.assertFalse((root / "rebooted").exists(), output)


if __name__ == "__main__":
    unittest.main()
