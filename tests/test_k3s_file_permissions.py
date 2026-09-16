"""Contract tests for K3s configuration and credential file permissions."""

import os
import unittest

import yaml


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
ROLE_TASKS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "k3s_install", "tasks", "main.yml"
)
CONFIG_TEMPLATE_PATH = os.path.join(
    REPOSITORY_ROOT,
    "ansible",
    "roles",
    "k3s_install",
    "templates",
    "k3s-config.yaml.j2",
)


def _tasks_by_name():
    with open(ROLE_TASKS_PATH, encoding="utf-8") as tasks_file:
        tasks = yaml.safe_load(tasks_file)

    return {task["name"]: task for task in tasks if "name" in task}


class TestK3SFilePermissions(unittest.TestCase):
    def test_configuration_directory_is_traversable(self):
        task = _tasks_by_name()["Create K3s configuration directory"]
        file_config = task["ansible.builtin.file"]

        self.assertEqual(file_config["path"], "/etc/rancher/k3s")
        self.assertEqual(file_config["mode"], "0755")

    def test_server_logs_remain_private(self):
        task = _tasks_by_name()["Create K3s server logs directory"]

        self.assertEqual(task["ansible.builtin.file"]["mode"], "0700")

    def test_sensitive_configuration_files_are_private(self):
        tasks = _tasks_by_name()
        config = tasks["Generate K3s configuration from template"]
        registry = tasks["Copy k3s_registry.yaml to the registry filepath"]

        self.assertEqual(config["ansible.builtin.template"]["mode"], "0600")
        self.assertEqual(registry["ansible.builtin.copy"]["mode"], "0600")

    def test_kubeconfig_remains_readable_through_traversable_directory(self):
        with open(CONFIG_TEMPLATE_PATH, encoding="utf-8") as template_file:
            template = template_file.read()

        self.assertIn('write-kubeconfig-mode: "0644"', template)


if __name__ == "__main__":
    unittest.main()
