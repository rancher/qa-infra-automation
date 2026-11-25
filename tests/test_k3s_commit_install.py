"""Contract tests for installing K3s from a commit hash."""

import os
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

        self.assertEqual(install["environment"]["GITHUB_TOKEN"], "{{ k3s_github_token }}")
        self.assertEqual(
            _load("defaults", "main.yml")["k3s_github_token"],
            "{{ lookup('env', 'GITHUB_TOKEN') }}",
        )

    def test_a_missing_token_fails_before_anything_is_installed(self):
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


if __name__ == "__main__":
    unittest.main()
