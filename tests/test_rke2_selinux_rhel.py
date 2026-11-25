"""Contract tests for the RKE2 SELinux policy on RHEL-family hosts."""

import os
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
            "Restore the SELinux contexts RKE2 needs",
        ])

    def test_the_repository_is_signed_and_matches_the_os_major(self):
        repo = _step("Add the signed RKE2 SELinux policy repository")["ansible.builtin.yum_repository"]

        self.assertIs(repo["gpgcheck"], True)
        self.assertEqual(repo["gpgkey"], "https://{{ rke2_selinux_rpm_site }}/public.key")
        self.assertEqual(
            repo["baseurl"],
            "https://{{ rke2_selinux_rpm_site }}/rke2/stable/common/centos/"
            "{{ ansible_facts.distribution_major_version }}/noarch",
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
        argv = _step("Restore the SELinux contexts RKE2 needs")["ansible.builtin.command"]["argv"]

        self.assertEqual(argv[:3], ["restorecon", "-R", "-v"])
        self.assertIn("/var/lib/rancher", argv)


if __name__ == "__main__":
    unittest.main()
