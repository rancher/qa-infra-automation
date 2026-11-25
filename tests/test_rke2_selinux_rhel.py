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


class Rke2RhelSelinuxTest(unittest.TestCase):
    """A tarball install on RHEL has no rke2-selinux: rke2-server hangs on keycreate errors."""

    def test_the_policy_is_installed_before_rke2_starts(self):
        names = [task["name"] for task in _tasks()]

        self.assertLess(names.index(POLICY), names.index("Enable RKE2 service"))

    def test_the_policy_comes_from_the_rke2_common_repo(self):
        task = next(task for task in _tasks() if task["name"] == POLICY)
        script = task["ansible.builtin.shell"]

        self.assertIn("rpm -q rke2-selinux", script)
        self.assertIn("/rke2/stable/common/centos/${el}/noarch/", script)
        self.assertIn("{{ rke2_selinux_rpm_site }}", script)
        self.assertNotIn("failed_when", task)

    def test_only_selinux_enabled_rhel_online_installs(self):
        when = next(task for task in _tasks() if task["name"] == POLICY)["when"]

        self.assertIn('ansible_facts.os_family | default(\'\') == "RedHat"', when)
        self.assertIn('ansible_facts.selinux.status | default(\'disabled\') == "enabled"', when)
        self.assertIn('rke2_install_method == "online"', when)
        self.assertIn("rke2_install_selinux_policy | bool", when)

    def test_a_new_policy_relabels_the_data_dir(self):
        script = next(task for task in _tasks() if task["name"] == POLICY)["ansible.builtin.shell"]

        self.assertIn("restorecon -R /var/lib/rancher /etc/rancher /usr/local/bin", script)
        self.assertLess(script.index("install -y"), script.index("restorecon"))


if __name__ == "__main__":
    unittest.main()
