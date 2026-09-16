"""Contract tests for K3s configuration and credential file permissions."""

import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
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


def _runtime_task(value, config_root):
    if isinstance(value, dict):
        return {
            key: _runtime_task(item, config_root)
            for key, item in value.items()
            if key not in {"owner", "group"} or os.geteuid() == 0
        }
    if isinstance(value, list):
        return [_runtime_task(item, config_root) for item in value]
    if isinstance(value, str):
        return value.replace("/etc/rancher/k3s", config_root).replace(
            "/etc/rancher", os.path.dirname(config_root)
        )
    return value


def _permission_tasks(config_root):
    tasks = _tasks()
    end = next(
        index for index, task in enumerate(tasks)
        if task.get("name") == "Create K3s server logs directory"
    )
    return [_runtime_task(task, config_root) for task in tasks[1:end]]


def _run_permissions(temp_dir, config_root, check=False):
    playbook_path = os.path.join(temp_dir, "permissions.yml")
    with open(playbook_path, "w", encoding="utf-8") as playbook_file:
        yaml.safe_dump([{
            "hosts": "localhost",
            "connection": "local",
            "gather_facts": False,
            "tasks": _permission_tasks(config_root),
        }], playbook_file)
    executable = shutil.which("ansible-playbook") or os.path.join(
        os.path.dirname(sys.executable), "ansible-playbook"
    )
    environment = os.environ.copy()
    environment.update({
        "ANSIBLE_LOCAL_TEMP": os.path.join(temp_dir, "ansible-local"),
        "ANSIBLE_REMOTE_TEMP": os.path.join(temp_dir, "ansible-remote"),
        "OBJC_DISABLE_INITIALIZE_FORK_SAFETY": "YES",
    })
    return subprocess.run(
        [executable, "-i", "localhost,", playbook_path] + (["--check"] if check else []),
        env=environment,
        capture_output=True, text=True, timeout=90, check=False,
    )


def _nonroot_readable(path):
    child = os.fork()
    if child == 0:
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
        try:
            with open(path, "rb") as source:
                source.read()
        except PermissionError:
            os._exit(1)
        os._exit(0)
    _, result = os.waitpid(child, 0)
    return os.waitstatus_to_exitcode(result) == 0


class TestK3sFilePermissions(unittest.TestCase):
    @unittest.skipIf(
        sys.platform == "darwin" and os.environ.get("QA_RUN_ANSIBLE_RUNTIME_TESTS") != "1",
        "local Ansible execution requires running outside the macOS sandbox",
    )
    def test_symlinked_config_root_fails_without_touching_external_target(self):
        for link_kind in ("absolute", "relative", "dangling", "loop"):
            with self.subTest(link_kind=link_kind), tempfile.TemporaryDirectory() as temp_dir:
                parent = os.path.join(temp_dir, "rancher")
                os.mkdir(parent, mode=0o755)
                config_root = os.path.join(parent, "k3s")
                external = os.path.join(temp_dir, "external")
                nested = os.path.join(external, "private")
                os.makedirs(nested, mode=0o755)
                os.chmod(external, 0o700)
                paths = [parent, external, nested]
                for name in (".credentials", "k3s.yaml", "private/config.yaml.backup"):
                    path = os.path.join(external, name)
                    with open(path, "w", encoding="utf-8") as target:
                        target.write("dummy-external-content\n")
                    os.chmod(path, 0o644)
                    paths.append(path)
                if sys.platform == "linux" and os.geteuid() == 0:
                    for path in paths[1:]:
                        os.chown(path, 65533, 65533)
                destinations = {
                    "absolute": external,
                    "relative": "../external",
                    "dangling": "../missing-target",
                    "loop": "k3s",
                }
                os.symlink(destinations[link_kind], config_root)
                paths.append(config_root)

                def snapshot():
                    result = {}
                    for path in paths:
                        info = os.lstat(path)
                        result[path] = (
                            info.st_mode, info.st_uid, info.st_gid, info.st_ino,
                            info.st_mtime_ns, info.st_ctime_ns,
                        )
                        if stat.S_ISREG(info.st_mode):
                            with open(path, "rb") as source:
                                result[path] += (source.read(),)
                    return result

                before = snapshot()
                for check in (False, True, False):
                    result = _run_permissions(temp_dir, config_root, check=check)
                    output = result.stdout + result.stderr
                    self.assertNotEqual(result.returncode, 0, output)
                    self.assertIn("Refusing symlinked K3s configuration directory", output)
                    self.assertRegex(result.stdout, r"changed=0\s")
                    self.assertNotIn("TASK [Ensure K3s configuration directory exists]", output)
                    self.assertEqual(snapshot(), before)
                    self.assertEqual(os.readlink(config_root), destinations[link_kind])
                    self.assertFalse(os.path.exists(os.path.join(temp_dir, "missing-target")))

    @unittest.skipIf(
        sys.platform == "darwin" and os.environ.get("QA_RUN_ANSIBLE_RUNTIME_TESTS") != "1",
        "local Ansible execution requires running outside the macOS sandbox",
    )
    def test_fresh_permission_check_mode_does_not_create_directories(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            config_root = os.path.join(temp_dir, "rancher", "k3s")
            result = _run_permissions(temp_dir, config_root, check=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(os.path.exists(os.path.dirname(config_root)))

    @unittest.skipIf(
        sys.platform == "darwin" and os.environ.get("QA_RUN_ANSIBLE_RUNTIME_TESTS") != "1",
        "local Ansible execution requires running outside the macOS sandbox",
    )
    def test_fresh_and_legacy_ancestors_allow_kubeconfig_access(self):
        for initial_mode in (None, 0o700, 0o750, 0o755):
            with self.subTest(initial_mode=initial_mode), tempfile.TemporaryDirectory() as temp_dir:
                os.chmod(temp_dir, 0o755)
                parent = os.path.join(temp_dir, "rancher")
                config_root = os.path.join(parent, "k3s")
                secrets = []
                if initial_mode is not None:
                    os.makedirs(config_root, mode=0o700)
                    os.chmod(parent, initial_mode)
                    os.mkdir(os.path.join(config_root, "private"), mode=0o755)
                    for name in (".hidden.yaml", "private/k3s.yaml"):
                        secret = os.path.join(config_root, name)
                        with open(secret, "w", encoding="utf-8") as target:
                            target.write("dummy-private-config\n")
                        os.chmod(secret, 0o644)
                        secrets.append(secret)
                result = _run_permissions(temp_dir, config_root)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(
                    stat.S_IMODE(os.stat(parent).st_mode),
                    (initial_mode if initial_mode is not None else 0o700) | 0o111,
                )
                self.assertEqual(stat.S_IMODE(os.stat(config_root).st_mode), 0o755)
                kubeconfig = os.path.join(config_root, "k3s.yaml")
                with open(kubeconfig, "w", encoding="utf-8") as target:
                    target.write("dummy-kubeconfig\n")
                os.chmod(kubeconfig, 0o644)
                if sys.platform == "linux" and os.geteuid() == 0:
                    self.assertTrue(_nonroot_readable(kubeconfig))
                for secret in secrets:
                    self.assertEqual(stat.S_IMODE(os.stat(secret).st_mode), 0o600)
                    if sys.platform == "linux" and os.geteuid() == 0:
                        self.assertFalse(_nonroot_readable(secret))
                rerun = _run_permissions(temp_dir, config_root)
                self.assertEqual(rerun.returncode, 0, rerun.stdout + rerun.stderr)
                self.assertRegex(rerun.stdout, r"changed=0\s")

    @unittest.skipIf(
        sys.platform == "darwin" and os.environ.get("QA_RUN_ANSIBLE_RUNTIME_TESTS") != "1",
        "local Ansible execution requires running outside the macOS sandbox",
    )
    def test_private_ancestor_does_not_expose_sibling_configuration(self):
        for sibling_name in ("registries.yaml", ".credentials", "rke2"):
            with self.subTest(sibling=sibling_name), tempfile.TemporaryDirectory() as temp_dir:
                parent = os.path.join(temp_dir, "rancher")
                config_root = os.path.join(parent, "k3s")
                os.makedirs(config_root, mode=0o700)
                os.chmod(parent, 0o700)
                sibling = os.path.join(parent, sibling_name)
                if sibling_name == "rke2":
                    os.mkdir(sibling, mode=0o755)
                else:
                    with open(sibling, "w", encoding="utf-8") as target:
                        target.write("dummy-private-config\n")
                    os.chmod(sibling, 0o644)
                before = os.stat(sibling)
                result = _run_permissions(temp_dir, config_root)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Secure those entries", result.stdout)
                self.assertEqual(stat.S_IMODE(os.stat(parent).st_mode), 0o700)
                self.assertEqual(os.stat(sibling).st_mode, before.st_mode)
                self.assertEqual(os.stat(sibling).st_mtime_ns, before.st_mtime_ns)

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
        link_find_name = "Find existing K3s configuration symlinks"
        secure_name = "Secure existing K3s sensitive configuration files"
        open_name = "Make K3s configuration directory traversable"

        self.assertLess(task_names.index(prepare_name), task_names.index(find_name))
        self.assertLess(task_names.index(find_name), task_names.index(link_find_name))
        self.assertLess(task_names.index(link_find_name), task_names.index(secure_name))
        self.assertLess(task_names.index(secure_name), task_names.index(open_name))

        prepare = tasks_by_name[prepare_name]["ansible.builtin.file"]
        existing = tasks_by_name[find_name]["ansible.builtin.find"]
        secure = tasks_by_name[secure_name]

        self.assertEqual(
            prepare["mode"],
            "{{ omit if k3s_install_config_directory.stat.exists else '0700' }}",
        )
        self.assertNotIn("patterns", existing)
        self.assertNotIn("excludes", existing)
        self.assertTrue(existing["hidden"])
        self.assertTrue(existing["recurse"])
        self.assertEqual(
            tasks_by_name[find_name]["register"],
            "k3s_install_sensitive_config_files",
        )
        self.assertEqual(secure["ansible.builtin.file"]["mode"], "0600")
        self.assertIn(
            "k3s_install_sensitive_config_files.files", secure["loop"]
        )
        self.assertEqual(
            secure["when"], "item.path != '/etc/rancher/k3s/k3s.yaml'"
        )

    def test_symlinks_stop_migration_before_directory_opens(self):
        tasks = _tasks()
        tasks_by_name = _tasks_by_name()
        task_names = [task.get("name") for task in tasks]

        find_name = "Find existing K3s configuration symlinks"
        close_name = "Keep K3s configuration private when symlinks are present"
        fail_name = "Refuse to expose K3s configuration symlinks"
        open_name = "Make K3s configuration directory traversable"
        find_task = tasks_by_name[find_name]
        find_config = find_task["ansible.builtin.find"]
        close_task = tasks_by_name[close_name]
        fail_task = tasks_by_name[fail_name]

        self.assertLess(task_names.index(find_name), task_names.index(close_name))
        self.assertLess(task_names.index(close_name), task_names.index(fail_name))
        self.assertLess(task_names.index(fail_name), task_names.index(open_name))
        self.assertEqual(find_config["file_type"], "link")
        self.assertTrue(find_config["hidden"])
        self.assertTrue(find_config["recurse"])
        self.assertEqual(close_task["ansible.builtin.file"]["mode"], "0700")
        self.assertEqual(
            close_task["when"], "k3s_install_config_links.matched | int > 0"
        )
        self.assertEqual(
            fail_task["when"], "k3s_install_config_links.matched | int > 0"
        )

    @unittest.skipIf(
        sys.platform == "darwin"
        and os.environ.get("QA_RUN_ANSIBLE_RUNTIME_TESTS") != "1",
        "local Ansible execution requires running outside the macOS sandbox",
    )
    def test_symlink_migration_fails_with_parent_private_at_runtime(self):
        task_names = (
            "Check for existing K3s configuration directory",
            "Refuse symlinked K3s configuration directory",
            "Ensure K3s configuration directory exists",
            "Find existing K3s sensitive configuration files",
            "Find existing K3s configuration symlinks",
            "Keep K3s configuration private when symlinks are present",
            "Refuse to expose K3s configuration symlinks",
            "Secure existing K3s sensitive configuration files",
            "Make K3s configuration directory traversable",
        )
        tasks_by_name = _tasks_by_name()

        with tempfile.TemporaryDirectory() as temp_dir:
            config_root = os.path.join(temp_dir, "k3s")
            private_dir = os.path.join(config_root, "private")
            os.makedirs(private_dir, mode=0o755)
            secret_path = os.path.join(private_dir, "registries.yaml")
            with open(secret_path, "w", encoding="utf-8") as secret_file:
                secret_file.write("password: sentinel\n")
            os.chmod(secret_path, 0o644)
            os.symlink("private/registries.yaml", os.path.join(config_root, "registries.yaml"))
            os.chmod(config_root, 0o700)

            runtime_tasks = [
                _runtime_task(tasks_by_name[name], config_root) for name in task_names
            ]
            playbook_path = os.path.join(temp_dir, "permission-regression.yml")
            with open(playbook_path, "w", encoding="utf-8") as playbook_file:
                yaml.safe_dump(
                    [
                        {
                            "name": "Exercise K3s permission migration",
                            "hosts": "localhost",
                            "connection": "local",
                            "gather_facts": False,
                            "tasks": runtime_tasks,
                        }
                    ],
                    playbook_file,
                    sort_keys=False,
                )

            ansible_playbook = shutil.which("ansible-playbook") or os.path.join(
                os.path.dirname(sys.executable), "ansible-playbook"
            )
            self.assertTrue(os.path.exists(ansible_playbook))
            environment = os.environ.copy()
            environment.update(
                {
                    "ANSIBLE_FORKS": "1",
                    "ANSIBLE_HOME": os.path.join(temp_dir, "ansible-home"),
                    "ANSIBLE_LOCAL_TEMP": os.path.join(temp_dir, "ansible-local"),
                    "ANSIBLE_REMOTE_TEMP": os.path.join(temp_dir, "ansible-remote"),
                    "OBJC_DISABLE_INITIALIZE_FORK_SAFETY": "YES",
                }
            )
            result = subprocess.run(
                [ansible_playbook, "-i", "localhost,", playbook_path],
                capture_output=True,
                check=False,
                env=environment,
                text=True,
                timeout=90,
            )

            output = result.stdout + result.stderr
            self.assertNotEqual(result.returncode, 0, output)
            self.assertIn("Refusing to make", output)
            self.assertEqual(stat.S_IMODE(os.stat(config_root).st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(os.stat(secret_path).st_mode), 0o644)

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
