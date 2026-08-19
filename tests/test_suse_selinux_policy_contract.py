"""Contract tests for safe SUSE SELinux policy integration."""

import base64
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
RKE2_INSTALL_TASKS = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "rke2_install", "tasks", "main.yml"
)
SUSE_POLICY_TASKS = os.path.join(
    REPOSITORY_ROOT,
    "ansible",
    "roles",
    "suse_selinux_policy",
    "tasks",
    "main.yml",
)


def _walk_tasks(tasks):
    for task in tasks:
        yield task
        for section in ("block", "rescue", "always"):
            yield from _walk_tasks(task.get(section, []) or [])


def _load_tasks(path):
    with open(path, encoding="utf-8") as tasks_file:
        return list(_walk_tasks(yaml.safe_load(tasks_file)))


def _task(tasks, name_prefix):
    for task in tasks:
        if task.get("name", "").startswith(name_prefix):
            return task
    raise AssertionError(f"Task starting with {name_prefix!r} was not found")


@unittest.skipIf(yaml is None, "pyyaml is required")
class TestSUSESELinuxPolicyContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rke2_tasks = _load_tasks(RKE2_INSTALL_TASKS)
        cls.policy_tasks = _load_tasks(SUSE_POLICY_TASKS)

    def test_rke2_airgap_verifies_policy_without_online_installation(self):
        include = _task(self.rke2_tasks, "Ensure the RKE2 SELinux policy")
        conditions = include.get("when", [])
        self.assertIn("rke2_install_selinux_policy | bool", conditions)
        self.assertEqual(
            include["vars"].get("suse_selinux_offline"),
            "{{ rke2_install_method == 'airgap' }}",
        )

        verify_offline = _task(self.policy_tasks, "Verify the offline SUSE")
        self.assertIn("ansible.builtin.assert", verify_offline)
        self.assertEqual(verify_offline.get("when"), "suse_selinux_offline | bool")

        install = _task(self.policy_tasks, "Install a valid")
        self.assertIn("not suse_selinux_offline | bool", install.get("when", []))

    def test_existing_common_repositories_are_never_deleted(self):
        task_names = [task.get("name", "") for task in self.policy_tasks]
        self.assertFalse(
            any(name.startswith("Remove existing Rancher") for name in task_names)
        )

        find_task = _task(self.policy_tasks, "Find existing Rancher")
        self.assertIn("contains", find_task["ansible.builtin.find"])
        self.assertEqual(find_task["ansible.builtin.find"].get("patterns"), "*.repo")

        reject_duplicates = _task(self.policy_tasks, "Reject duplicate Rancher")
        duplicate_check = reject_duplicates["ansible.builtin.assert"]["that"][0]
        self.assertIn("suse_selinux_existing_common_aliases", duplicate_check)
        self.assertIn("unique", duplicate_check)

    @unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
    def test_duplicate_detection_compares_aliases_not_file_count(self):
        initialize = _task(self.policy_tasks, "Initialize existing Rancher")
        record = _task(
            self.policy_tasks,
            "Record existing Rancher {{ suse_selinux_product }} common aliases",
        )
        reject = _task(self.policy_tasks, "Reject duplicate Rancher")

        cases = [
            (["stable", "testing"], True),
            (["stable", "stable"], False),
        ]
        for aliases, should_pass in cases:
            with self.subTest(aliases=aliases):
                results = []
                for index, alias in enumerate(aliases):
                    content = f"[rancher-rke2-common-{alias}]\n"
                    results.append(
                        {
                            "item": f"/tmp/repository-{index}.repo",
                            "content": base64.b64encode(content.encode()).decode(),
                        }
                    )

                play = {
                    "name": "Repository alias validation",
                    "hosts": "localhost",
                    "connection": "local",
                    "gather_facts": False,
                    "vars": {
                        "suse_selinux_product": "rke2",
                        "suse_selinux_existing_common_repository_contents": {
                            "results": results
                        },
                    },
                    "tasks": [initialize, record, reject],
                }
                with tempfile.TemporaryDirectory() as temporary_directory:
                    playbook_path = os.path.join(temporary_directory, "playbook.yml")
                    with open(playbook_path, "w", encoding="utf-8") as playbook_file:
                        playbook_file.write(yaml.safe_dump([play]))
                    environment = os.environ.copy()
                    environment["ANSIBLE_LOCAL_TEMP"] = os.path.join(
                        temporary_directory, "ansible-local"
                    )
                    result = subprocess.run(
                        ["ansible-playbook", "-i", "localhost,", playbook_path],
                        cwd=REPOSITORY_ROOT,
                        env=environment,
                        capture_output=True,
                        text=True,
                        check=False,
                    )

                if should_pass:
                    self.assertEqual(
                        result.returncode, 0, msg=result.stdout + result.stderr
                    )
                else:
                    self.assertNotEqual(result.returncode, 0)

    def test_requested_channel_is_created_and_selected_explicitly(self):
        configure = _task(self.policy_tasks, "Configure the Rancher")
        self.assertEqual(
            configure.get("when"),
            "suse_selinux_requested_common_alias not in "
            "suse_selinux_existing_common_aliases",
        )
        self.assertEqual(
            configure["ansible.builtin.copy"].get("dest"),
            "/etc/zypp/repos.d/{{ suse_selinux_requested_common_alias }}.repo",
        )

        task_names = [task.get("name", "") for task in self.policy_tasks]
        self.assertNotIn("Import the Rancher RPM signing key", task_names)

        refresh = _task(self.policy_tasks, "Refresh the selected Rancher")
        self.assertEqual(
            refresh["ansible.builtin.command"]["argv"][-1],
            "{{ suse_selinux_requested_common_alias }}",
        )

        install = _task(self.policy_tasks, "Install {{ suse_selinux_product }}-selinux")
        install_argv = install["ansible.builtin.command"]["argv"]
        self.assertEqual(
            install_argv,
            [
                "zypper",
                "--non-interactive",
                "--gpg-auto-import-keys",
                "install",
                "--from",
                "{{ suse_selinux_requested_common_alias }}",
                "{{ suse_selinux_product }}-selinux",
            ],
        )

        transactional_install = _task(
            self.policy_tasks,
            "Install {{ suse_selinux_product }}-selinux via transactional-update",
        )
        self.assertIn(
            "--from {{ suse_selinux_requested_common_alias }}",
            transactional_install["ansible.builtin.command"]["cmd"],
        )


if __name__ == "__main__":
    unittest.main()
