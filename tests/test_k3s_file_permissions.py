"""Contract tests for K3s configuration and credential file permissions."""

import fnmatch
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

        prepare_name = "Ensure K3s configuration directory exists"
        find_name = "Find existing K3s sensitive configuration files"
        drop_in_find_name = "Find existing K3s configuration drop-ins"
        secure_name = "Secure existing K3s sensitive configuration files"
        open_name = "Make K3s configuration directory traversable"

        self.assertLess(task_names.index(prepare_name), task_names.index(find_name))
        self.assertLess(
            task_names.index(find_name), task_names.index(drop_in_find_name)
        )
        self.assertLess(
            task_names.index(drop_in_find_name), task_names.index(secure_name)
        )
        self.assertLess(task_names.index(secure_name), task_names.index(open_name))

        prepare = tasks_by_name[prepare_name]["ansible.builtin.file"]
        existing = tasks_by_name[find_name]["ansible.builtin.find"]
        secure = tasks_by_name[secure_name]

        self.assertEqual(
            prepare["mode"],
            "{{ omit if k3s_install_config_directory.stat.exists else '0700' }}",
        )
        self.assertEqual(
            existing["excludes"],
            ["k3s.yaml"],
        )
        self.assertNotIn("patterns", existing)
        self.assertTrue(existing["hidden"])
        self.assertEqual(
            tasks_by_name[find_name]["register"],
            "k3s_install_sensitive_config_files",
        )
        self.assertEqual(secure["ansible.builtin.file"]["mode"], "0600")
        self.assertIn(
            "k3s_install_sensitive_config_files.files", secure["loop"]
        )

    def test_configuration_drop_ins_are_secured_before_directory_opens(self):
        tasks = _tasks()
        tasks_by_name = _tasks_by_name()
        task_names = [task.get("name") for task in tasks]

        find_name = "Find existing K3s configuration drop-ins"
        secure_name = "Secure existing K3s sensitive configuration files"
        open_name = "Make K3s configuration directory traversable"
        find_task = tasks_by_name[find_name]
        find_config = find_task["ansible.builtin.find"]
        secure_loop = tasks_by_name[secure_name]["loop"]

        self.assertLess(task_names.index(find_name), task_names.index(secure_name))
        self.assertLess(task_names.index(secure_name), task_names.index(open_name))
        self.assertEqual(find_config["paths"], "/etc/rancher/k3s/config.yaml.d")
        self.assertNotIn("patterns", find_config)
        self.assertTrue(find_config["hidden"])
        self.assertTrue(find_config["recurse"])
        self.assertEqual(
            find_task["when"],
            "k3s_install_config_drop_in_directory.stat.isdir | default(false)",
        )
        self.assertIn("k3s_install_sensitive_config_drop_ins.files", secure_loop)

    def test_hidden_and_symlinked_drop_ins_stay_behind_private_directory(self):
        tasks = _tasks()
        tasks_by_name = _tasks_by_name()
        task_names = [task.get("name") for task in tasks]

        private_name = "Keep existing K3s configuration drop-ins private"
        open_name = "Make K3s configuration directory traversable"
        stat_task = tasks_by_name["Check for existing K3s configuration drop-ins"]
        private_task = tasks_by_name[private_name]
        private_config = private_task["ansible.builtin.file"]

        self.assertLess(task_names.index(private_name), task_names.index(open_name))
        self.assertTrue(stat_task["ansible.builtin.stat"]["follow"])
        self.assertEqual(private_config["path"], "/etc/rancher/k3s/config.yaml.d")
        self.assertEqual(private_config["mode"], "0700")
        self.assertTrue(private_config["follow"])

    def test_hidden_drop_ins_and_backups_are_not_filtered_out(self):
        find_task = _tasks_by_name()["Find existing K3s configuration drop-ins"]
        find_config = find_task["ansible.builtin.find"]
        patterns = find_config.get("patterns", ["*"])

        self.assertEqual(find_config["file_type"], "file")
        self.assertNotIn("patterns", find_config)
        self.assertTrue(find_config["hidden"])
        for backup_name in (
            ".secret.yaml",
            "secret.yaml.bak",
            "secret.yaml.123456~",
        ):
            self.assertTrue(
                any(fnmatch.fnmatch(backup_name, pattern) for pattern in patterns)
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
