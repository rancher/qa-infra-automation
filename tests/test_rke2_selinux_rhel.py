"""Contract tests for the RKE2 SELinux policy on RHEL-family hosts."""

import configparser
import copy
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


ROLE_TASKS = os.path.join(
    os.path.dirname(__file__), "..", "ansible", "roles", "rke2_install", "tasks", "main.yml"
)
POLICY = "Ensure the RKE2 SELinux policy on RHEL-family hosts"


def _tasks():
    with open(ROLE_TASKS, encoding="utf-8") as tasks_file:
        return [task for task in yaml.safe_load(tasks_file) if "name" in task]


def _policy_block():
    return next(task for task in _tasks() if task["name"] == POLICY)


def _step(name):
    return next(task for task in _policy_block()["block"] if task["name"] == name)


class Rke2RhelSelinuxTest(unittest.TestCase):
    """A tarball install on RHEL has no rke2-selinux: rke2-server hangs on keycreate errors."""

    def test_the_policy_is_installed_before_rke2_starts(self):
        names = [task["name"] for task in _tasks()]
        steps = [task["name"] for task in _policy_block()["block"]]

        self.assertLess(names.index(POLICY), names.index("Enable RKE2 service"))
        self.assertEqual(steps, [
            "Add the signed RKE2 SELinux policy repository",
            "Install the rke2-selinux policy",
            "Find the installed RKE2 paths for SELinux relabeling",
            "Restore the SELinux contexts RKE2 needs",
        ])

    def test_the_repository_is_signed_and_matches_the_os_major(self):
        repo = _step("Add the signed RKE2 SELinux policy repository")["ansible.builtin.yum_repository"]

        self.assertIs(repo["gpgcheck"], True)
        self.assertEqual(repo["gpgkey"], "https://{{ rke2_selinux_rpm_site }}/public.key")
        self.assertEqual(
            repo["baseurl"],
            "https://{{ rke2_selinux_rpm_site }}/rke2/stable/common/centos/"
            "{{ rke2_install_selinux_el_major }}/noarch",
        )
        self.assertNotEqual(repo["name"], "rancher-rke2-common")

    def test_the_policy_package_is_installed_without_skipping_signatures(self):
        install = _step("Install the rke2-selinux policy")

        self.assertEqual(install["ansible.builtin.package"], {"name": "rke2-selinux", "state": "present"})
        self.assertNotIn("nogpgcheck", yaml.safe_dump(_policy_block()))
        self.assertNotIn("disable_gpg_check", install["ansible.builtin.package"])

    def test_only_selinux_enabled_rhel_online_installs(self):
        when = _policy_block()["when"]

        self.assertIn('ansible_facts.os_family | default(\'\') == "RedHat"', when)
        self.assertIn('ansible_facts.selinux.status | default(\'disabled\') == "enabled"', when)
        self.assertIn('rke2_install_method == "online"', when)
        self.assertIn("rke2_install_selinux_policy | bool", when)

    def test_the_relabel_covers_the_data_dir(self):
        paths = _step("Find the installed RKE2 paths for SELinux relabeling")["loop"]

        self.assertIn("{{ rke2_data_dir }}", paths)
        self.assertNotIn("/var/lib/rancher", paths)
        self.assertNotIn("/etc/rancher", paths)
        self.assertNotIn("/usr/local/bin", paths)

    @unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
    def test_relabel_only_existing_rke2_paths_with_ansible(self):
        cases = {
            "rpm": "/usr/bin/rke2", "tar": "/usr/local/bin/rke2",
            "opt": "/opt/rke2/bin/rke2", "custom": "/srv/rke2/bin/rke2", "absent": None,
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / "tools"
            tools.mkdir()
            restorecon = tools / "restorecon"
            restorecon.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$RELABEL_LOG"\n', encoding="utf-8")
            restorecon.chmod(0o755)
            plays, expected = [], {}

            for name, binary in cases.items():
                host = root / name
                data = host / "var/lib/rancher/rke2"
                config = host / "etc/rancher/rke2"
                data.mkdir(parents=True)
                config.mkdir(parents=True)
                unrelated = host / "usr/local/bin/unrelated-tool"
                unrelated.parent.mkdir(parents=True)
                unrelated.touch()
                paths = [str(data), str(config)]
                if binary:
                    installed = host / binary.lstrip("/")
                    installed.parent.mkdir(parents=True, exist_ok=True)
                    installed.touch()
                    paths.append(str(installed))

                discover = copy.deepcopy(_step("Find the installed RKE2 paths for SELinux relabeling"))
                discover["loop"] = [str(host) + path if path.startswith("/") else path
                                    for path in discover["loop"]]
                log = host / "relabel.log"
                expected[log] = [arg for path in paths for arg in ["-R", "-v", path]]
                plays.append({
                    "hosts": "localhost", "gather_facts": False,
                    "vars": {
                        "ansible_python_interpreter": sys.executable,
                        "rke2_data_dir": str(data),
                        "rke2_bin_dir": str(host / ("srv/rke2/bin" if name == "custom" else "usr/local/bin")),
                    },
                    "environment": {"PATH": str(tools) + os.pathsep + os.environ["PATH"], "RELABEL_LOG": str(log)},
                    "tasks": [discover, _step("Restore the SELinux contexts RKE2 needs")],
                })

            playbook = root / "relabel.yml"
            playbook.write_text(yaml.safe_dump(plays), encoding="utf-8")
            for _ in range(2):
                for log in expected:
                    log.write_text("", encoding="utf-8")
                result = subprocess.run(
                    ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
                    text=True, capture_output=True, timeout=90,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertRegex(result.stdout, r"changed=0\s")
                for log, args in expected.items():
                    self.assertEqual(log.read_text(encoding="utf-8").splitlines(), args)

    @unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
    def test_repository_mapping_with_ansible(self):
        cases = [("RedHat", major, major) for major in ("7", "8", "9", "10")]
        cases += [("Fedora", "43", "8"), ("Amazon", "2023", "8")]

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plays = []
            for distribution, major, _ in cases:
                repos = root / f"{distribution}-{major}"
                repos.mkdir()
                policy = copy.deepcopy(_policy_block())
                policy.pop("become")
                policy["block"] = [policy["block"][0]]
                policy["block"][0]["ansible.builtin.yum_repository"]["reposdir"] = str(repos)
                plays.append({
                    "hosts": "localhost",
                    "gather_facts": False,
                    "vars": {
                        "ansible_python_interpreter": sys.executable,
                        "ansible_facts": {
                            "os_family": "RedHat",
                            "distribution": distribution,
                            "distribution_major_version": major,
                            "selinux": {"status": "enabled"},
                        },
                        "rke2_install_selinux_policy": True,
                        "rke2_install_method": "online",
                        "rke2_selinux_rpm_site": "rpm.example.invalid",
                    },
                    "tasks": [policy],
                })

            playbook = root / "repos.yml"
            playbook.write_text(yaml.safe_dump(plays), encoding="utf-8")
            for attempt in range(2):
                result = subprocess.run(
                    ["ansible-playbook", "-i", "localhost,", "-c", "local", str(playbook)],
                    text=True, capture_output=True, timeout=60,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                if attempt == 1:
                    self.assertRegex(result.stdout, r"changed=0\s")

            for distribution, major, expected in cases:
                with self.subTest(distribution=distribution, major=major):
                    config = configparser.ConfigParser()
                    config.read(root / f"{distribution}-{major}" / "rancher-rke2-selinux.repo")
                    repo = config["rancher-rke2-selinux"]
                    self.assertEqual(
                        repo["baseurl"],
                        f"https://rpm.example.invalid/rke2/stable/common/centos/{expected}/noarch",
                    )
                    self.assertTrue(repo.getboolean("gpgcheck"))
                    self.assertEqual(repo["gpgkey"], "https://rpm.example.invalid/public.key")


if __name__ == "__main__":
    unittest.main()
