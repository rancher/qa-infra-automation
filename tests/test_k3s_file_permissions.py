"""Contract tests for K3s configuration and credential file permissions."""

import os
import re
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


def _tasks():
    with open(ROLE_TASKS_PATH, encoding="utf-8") as tasks_file:
        return yaml.safe_load(tasks_file)


def _tasks_by_name():
    return {task["name"]: task for task in _tasks() if "name" in task}


class TestK3sFilePermissions(unittest.TestCase):
    def test_configuration_directory_is_traversable(self):
        task = _tasks_by_name()["Make K3s configuration directory traversable"]
        file_config = task["ansible.builtin.file"]

        self.assertEqual(file_config["path"], "/etc/rancher/k3s")
        self.assertEqual(file_config["mode"], "0755")

    def test_existing_sensitive_files_are_secured_before_directory_opens(self):
        tasks = _tasks()
        tasks_by_name = _tasks_by_name()
        task_names = [task.get("name") for task in tasks]

        prepare_name = "Prepare K3s configuration directory privately"
        find_name = "Find existing K3s sensitive configuration files"
        secure_name = "Secure existing K3s sensitive configuration files"
        open_name = "Make K3s configuration directory traversable"

        self.assertLess(task_names.index(prepare_name), task_names.index(find_name))
        self.assertLess(task_names.index(find_name), task_names.index(secure_name))
        self.assertLess(task_names.index(secure_name), task_names.index(open_name))

        prepare = tasks_by_name[prepare_name]["ansible.builtin.file"]
        existing = tasks_by_name[find_name]["ansible.builtin.find"]
        secure = tasks_by_name[secure_name]

        self.assertEqual(prepare["mode"], "0700")
        self.assertEqual(
            set(existing["patterns"]),
            {"config.yaml", "config.yaml.*", "registries.yaml", "registries.yaml.*"},
        )
        self.assertEqual(
            tasks_by_name[find_name]["register"],
            "k3s_install_sensitive_config_files",
        )
        self.assertEqual(secure["ansible.builtin.file"]["mode"], "0600")
        self.assertEqual(
            secure["loop"], "{{ k3s_install_sensitive_config_files.files }}"
        )

    def test_server_logs_remain_private(self):
        task = _tasks_by_name()["Create K3s server logs directory"]

        self.assertEqual(task["ansible.builtin.file"]["mode"], "0700")

    def test_sensitive_configuration_files_are_private(self):
        tasks = _tasks_by_name()
        config = tasks["Generate K3s configuration from template"]
        registry = tasks["Copy k3s_registry.yaml to the registry filepath"]

        self.assertEqual(config["ansible.builtin.template"]["mode"], "0600")
        self.assertFalse(config["ansible.builtin.template"]["backup"])
        self.assertEqual(registry["ansible.builtin.copy"]["mode"], "0600")

    def test_kubeconfig_remains_readable_through_traversable_directory(self):
        with open(CONFIG_TEMPLATE_PATH, encoding="utf-8") as template_file:
            template = template_file.read()

        self.assertRegex(
            template,
            re.compile(
                r"^\s*write-kubeconfig-mode:\s*['\"]?0644['\"]?\s*$",
                re.MULTILINE,
            ),
        )


if __name__ == "__main__":
    unittest.main()
