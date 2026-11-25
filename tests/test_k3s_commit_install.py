"""Contract tests for installing K3s from a commit hash."""

import functools
import hashlib
import http.server
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

import yaml


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
ROLE_PATH = os.path.join(REPOSITORY_ROOT, "ansible", "roles", "k3s_install")


def _load(*parts):
    with open(os.path.join(ROLE_PATH, *parts), encoding="utf-8") as yaml_file:
        return yaml.safe_load(yaml_file)


def _commit_block():
    return next(
        task for task in _load("tasks", "main.yml")
        if task.get("name") == "Install K3s from commit hash via install script"
    )

def _commit_block_tasks():
    return _commit_block()["block"]


class K3sCommitInstallTest(unittest.TestCase):
    """get.k3s.io refuses commit builds without jq, unzip and GITHUB_TOKEN."""

    def test_tools_are_installed_before_the_script_runs(self):
        names = [task["name"] for task in _commit_block_tasks()]
        for package in ("jq", "unzip"):
            name = f"Install {package} for the commit install script"
            task = next(task for task in _commit_block_tasks() if task["name"] == name)
            install = task.get("block", [task])[0]

            self.assertEqual(install["ansible.builtin.package"]["name"], package)
            self.assertLess(names.index(name), names.index("Install K3s via install script"))

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
            names.index("Install unzip for the commit install script"),
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
                **_load("defaults", "main.yml"),
                "k3s_install_jq_temp": {},
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
            "ANSIBLE_ROLES_PATH": str(Path(ROLE_PATH).resolve().parent),
            "OBJC_DISABLE_INITIALIZE_FORK_SAFETY": "YES",
        }
        result = subprocess.run(
            ["ansible-playbook", "-vvv", "-i", "localhost,", str(playbook)],
            env=environment, capture_output=True, text=True, timeout=60, check=False,
        )
        output = result.stdout + result.stderr + (root / "ansible.log").read_text(encoding="utf-8")
        return result.returncode, output

    def test_token_reaches_installer_without_leaking_on_success_or_failure(self):
        for failed_attempts in (0, 2, 4):
            with self.subTest(failed_attempts=failed_attempts), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                token = "dummy-token.with+regex[characters]?"
                installer = root / "installer.sh"
                installer.write_text(
                    f'test "$GITHUB_TOKEN" = "{token}" || exit 91\n'
                    'test "$INSTALL_K3S_COMMIT" = "0123456789abcdef" || exit 92\n'
                    'test "$INSTALL_K3S_EXEC" = "agent" || exit 93\n'
                    'test "$INSTALL_K3S_SKIP_START" = "true" || exit 94\n'
                    f'count=$(cat "{root / "attempts"}" 2>/dev/null || echo 0)\n'
                    'count=$((count + 1))\n'
                    f'printf "%s\\n" "$count" > "{root / "attempts"}"\n'
                    'printf "old-output-marker\\n"\n'
                    'printf "%3000s\\n" " "\n'
                    'printf "%s%1980s\\n" "$GITHUB_TOKEN" " "\n'
                    'printf "artifact download failed: %s\\n" "$GITHUB_TOKEN" >&2\n'
                    f'[ "$count" -le {failed_attempts} ] && exit 22\n'
                    'exit 0\n', encoding="utf-8",
                )
                task = next(t for t in _commit_block_tasks() if t["name"] == "Install K3s via install script")
                task["ansible.builtin.shell"] = task["ansible.builtin.shell"].replace(
                    "/tmp/k3s-install.sh", str(installer),
                )
                task["delay"] = 0
                report = next(t for t in _commit_block_tasks() if "ansible.builtin.fail" in t)
                following = {"ansible.builtin.file": {"path": str(root / "continued"), "state": "touch"}}

                rc, output = self._run(root, [task, report, following], token=token)

                succeeded = failed_attempts < 4
                self.assertEqual(rc == 0, succeeded, output)
                self.assertEqual((root / "continued").exists(), succeeded, output)
                self.assertEqual(int((root / "attempts").read_text()), min(failed_attempts + 1, 4))
                self.assertNotIn(token, output)
                self.assertNotIn("regex[characters]?", output)
                self.assertNotIn("old-output-marker", output)
                if not succeeded:
                    self.assertIn("artifact download failed: [REDACTED]", output)
                    self.assertIn("rc=22", output)

    def test_missing_token_stops_before_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            check = next(t for t in _commit_block_tasks() if t["name"] == "Require a GitHub token for commit installs")
            marker = {"ansible.builtin.file": {"path": str(root / "installed"), "state": "touch"}}

            rc, output = self._run(root, [check, marker])

            self.assertNotEqual(rc, 0, output)
            self.assertIn("needs GITHUB_TOKEN", output)
            self.assertFalse((root / "installed").exists())

    def _fallback_tasks(self, root, base_url, package_rc):
        block = _commit_block()
        for task in block["block"]:
            if "ansible.builtin.stat" in task:
                task["ansible.builtin.stat"]["path"] = str(root / "transactional-update")
            elif "ansible.builtin.package" in task:
                task.pop("ansible.builtin.package")
                task["ansible.builtin.command"] = {"argv": ["/bin/true"]}
            elif "block" in task:
                package = task["block"][0]
                package.pop("ansible.builtin.package")
                package["ansible.builtin.command"] = {
                    "argv": [sys.executable, "-c", f"raise SystemExit({package_rc})"],
                }
                for rescue in task["rescue"]:
                    if "ansible.builtin.include_tasks" in rescue:
                        rescue["ansible.builtin.include_tasks"] = str(
                            Path(ROLE_PATH).resolve() / "tasks" / "commit-jq-fallback.yml"
                        )
            elif "ansible.builtin.command" in task:
                task["environment"] = {"PATH": str(root / "bin")}
            elif "ansible.builtin.get_url" in task:
                task["ansible.builtin.get_url"].update({
                    "url": base_url + "/installer.sh", "dest": str(root / "installer.sh"),
                })
            elif "ansible.builtin.shell" in task:
                task["ansible.builtin.shell"] = task["ansible.builtin.shell"].replace(
                    "/tmp/k3s-install.sh", str(root / "installer.sh"),
                )
                task["delay"] = 0
            elif "ansible.builtin.file" in task:
                task["ansible.builtin.file"]["path"] = str(root / "installer.sh")

        return [block]

    def test_jq_fallback_verifies_download_scopes_errors_and_cleans_up(self):
        cases = (
            ("amd64", "x86_64", 104, False, "Suse", False, 0, True),
            ("arm64", "aarch64", 104, False, "Suse", False, 0, True),
            ("checksum mismatch", "x86_64", 104, False, "Suse", True, 0, False),
            ("installer failure", "x86_64", 104, False, "Suse", False, 22, True),
            ("package error", "x86_64", 7, False, "Suse", False, 0, False),
            ("transactional", "x86_64", 104, True, "Suse", False, 0, False),
            ("other OS", "x86_64", 104, False, "RedHat", False, 0, False),
            ("unsupported arch", "s390x", 104, False, "Suse", False, 0, False),
        )
        for name, arch, package_rc, transactional, os_family, corrupt, installer_rc, ran in cases:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = root / "source"
                source.mkdir()
                tools = root / "tools"
                tools.mkdir()
                active = root / "bin"
                active.mkdir()
                (active / "unzip").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                (active / "unzip").chmod(0o755)
                if transactional:
                    (root / "transactional-update").touch()

                body = b"#!/bin/sh\nprintf 'jq-fixture\\n'\n"
                assets = _load("defaults", "main.yml")["k3s_install_jq_assets"]
                for asset in assets.values():
                    (source / asset["name"]).write_bytes(body)
                    asset["sha256"] = "0" * 64 if corrupt else hashlib.sha256(body).hexdigest()
                (source / "installer.sh").write_text(
                    'test "$(jq --version)" = "jq-fixture" || exit 95\n'
                    f'touch "{root / "installed"}"\n'
                    f'exit {installer_rc}\n', encoding="utf-8",
                )
                handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(source))
                server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()

                try:
                    base_url = f"http://127.0.0.1:{server.server_port}"
                    rc, output = self._run(root, self._fallback_tasks(root, base_url, package_rc),
                                          token="fixture-token", variables={
                        "_k3s_is_commit": True, "_k3s_binary": {"stat": {"exists": False}},
                        "ansible_facts": {"os_family": os_family, "architecture": arch},
                        "k3s_install_jq_release_url": base_url, "k3s_install_jq_assets": assets,
                        "k3s_install_tools_parent": str(tools), "dv_retries": 0, "dv_delay": 0,
                    })
                finally:
                    server.shutdown()
                    thread.join(timeout=5)
                    server.server_close()

                self.assertEqual(rc == 0, ran and installer_rc == 0, output)
                self.assertEqual((root / "installed").exists(), ran, output)
                self.assertEqual(list(tools.iterdir()), [], output)
                self.assertNotIn("fixture-token", output)
                if corrupt:
                    self.assertIn("checksum", output.lower())
                if package_rc != 104 or transactional or os_family != "Suse":
                    self.assertNotIn("TASK [Download the pinned jq binary", output)

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
                    prerequisites = [
                        child for task in _commit_block_tasks()
                        for child in task.get("block", [task])
                    ]
                    for task in prerequisites:
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
                                str(target), *([packages] if isinstance(packages, str) else packages),
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
