"""Tests for the rke2-playbook install_method contract and cni wiring."""

import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

try:
    import yaml
except ImportError:  # pragma: no cover - pyyaml ships with ansible
    yaml = None


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
PLAYBOOK_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "rke2", "default", "rke2-playbook.yml"
)


def _role_invocation(role_name):
    """Return a static or dynamic role invocation from rke2-playbook.yml."""
    with open(PLAYBOOK_PATH, encoding="utf-8") as playbook_file:
        plays = yaml.safe_load(playbook_file)
    for play in plays:
        for role in play.get("roles", []):
            if isinstance(role, dict) and role.get("role") == role_name:
                return role
        for task in play.get("tasks", []) or []:
            include = task.get("ansible.builtin.include_role", {})
            if include.get("name") == role_name:
                return task

    raise AssertionError(f"role {role_name} not found in rke2-playbook.yml")


def _role_vars(role_name):
    """Return the vars dict of the given role invocation."""
    invocation = _role_invocation(role_name)
    if "vars" not in invocation:
        raise AssertionError(f"role {role_name} has no invocation vars")
    return invocation["vars"]


def _cis_resolve_task():
    """Return the cluster play's real 'CIS | Resolve effective config' task."""
    with open(PLAYBOOK_PATH, encoding="utf-8") as playbook_file:
        plays = yaml.safe_load(playbook_file)
    for play in plays:
        for task in play.get("pre_tasks", []) or []:
            if task.get("name") == "CIS | Resolve effective config":
                task = dict(task)
                task.pop("tags", None)
                return task

    raise AssertionError("CIS | Resolve effective config pre_task not found")


def _install_method_assert_task():
    """Return the playbook's real 'Validate install_method' pre_task."""
    with open(PLAYBOOK_PATH, encoding="utf-8") as playbook_file:
        plays = yaml.safe_load(playbook_file)
    for play in plays:
        for task in play.get("pre_tasks", []) or []:
            if task.get("name") == "Validate install_method":
                task = dict(task)
                task.pop("tags", None)
                return task

    raise AssertionError("Validate install_method pre_task not found")


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
@unittest.skipIf(yaml is None, "pyyaml is required")
class TestInstallMethodContract(unittest.TestCase):
    """install_method must honor both contracts: online|airgap and rpm|tar."""

    # (install_method input, expected network mode, expected installer method)
    CASES = [
        ("online", "online", ""),
        ("airgap", "airgap", ""),
        ("rpm", "online", "rpm"),
        ("tar", "online", "tar"),
        (None, "online", ""),  # unset -> role defaults
    ]

    def _run_playbook(self, playbook):
        with tempfile.TemporaryDirectory() as temporary_directory:
            playbook_path = os.path.join(temporary_directory, "playbook.yml")
            with open(playbook_path, "w", encoding="utf-8") as playbook_file:
                playbook_file.write(playbook)

            environment = os.environ.copy()
            environment["ANSIBLE_LOCAL_TEMP"] = os.path.join(
                temporary_directory, "ansible-local"
            )
            return subprocess.run(
                [
                    "ansible-playbook",
                    "-i",
                    "localhost,",
                    "--connection=local",
                    playbook_path,
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

    def test_install_method_mapping(self):
        install_vars = _role_vars("rke2_install")
        # evaluate the playbook's actual expressions, not copies of them
        mode_expr = install_vars["rke2_install_method"]
        installer_expr = install_vars["rke2_installer_method"]

        for value, expected_mode, expected_installer in self.CASES:
            with self.subTest(install_method=value if value is not None else "<unset>"):
                play = {
                    "name": "Evaluate install_method mapping",
                    "hosts": "localhost",
                    "gather_facts": False,
                    "vars": {
                        "resolved_mode": mode_expr,
                        "resolved_installer": installer_expr,
                    },
                    "tasks": [
                        {
                            "name": "Verify contract",
                            "ansible.builtin.assert": {
                                "that": [
                                    f"resolved_mode == '{expected_mode}'",
                                    f"resolved_installer == '{expected_installer}'",
                                ],
                                "fail_msg": (
                                    f"install_method={value!r} resolved to "
                                    "mode={{ resolved_mode }} "
                                    "installer={{ resolved_installer }}"
                                ),
                            },
                        }
                    ],
                }
                if value is not None:
                    play["vars"]["install_method"] = value
                result = self._run_playbook(yaml.safe_dump([play]))
                self.assertEqual(
                    result.returncode, 0, msg=result.stdout + result.stderr
                )

    def test_invalid_install_method_fails_fast(self):
        """A typo like 'rmp' must abort the play, not silently become online."""
        validate_task = _install_method_assert_task()

        cases = [("rmp", False), ("airgap", True), ("rpm", True), (None, True)]
        for value, should_pass in cases:
            with self.subTest(install_method=value if value is not None else "<unset>"):
                play = {
                    "name": "Validate install_method input",
                    "hosts": "localhost",
                    "gather_facts": False,
                    "tasks": [validate_task],
                }
                if value is not None:
                    play["vars"] = {"install_method": value}
                result = self._run_playbook(yaml.safe_dump([play]))
                if should_pass:
                    self.assertEqual(
                        result.returncode, 0, msg=result.stdout + result.stderr
                    )
                else:
                    self.assertNotEqual(
                        result.returncode, 0,
                        msg=f"install_method={value!r} was accepted",
                    )

    def test_cis_resolve_sees_manual_server_flags(self):
        """--tags cluster: CIS detection must read server_flags/worker_flags."""
        resolve_task = _cis_resolve_task()

        # (case, play vars, extra-vars, expected profile on the server side)
        cases = [
            (
                "manual server_flags reach the CIS resolve",
                {"server_flags": "profile: cis"},
                {},
                "cis",
            ),
            (
                "DTF additional config keeps precedence",
                {"server_flags": "profile: something-else"},
                {"rke2_additional_config": {"profile": "cis"}},
                "cis",
            ),
        ]
        for case, play_vars, extra_vars, expected in cases:
            with self.subTest(case=case):
                merged = {
                    "rke2_node_role": "master",
                    "node_roles": [],
                    "rke2_server_config": {},
                    "rke2_agent_config": {},
                }
                merged.update(play_vars)
                play = {
                    "name": f"CIS resolve: {case}",
                    "hosts": "localhost",
                    "gather_facts": False,
                    "vars": merged,
                    "tasks": [
                        resolve_task,
                        {
                            "name": "Verify effective profile",
                            "ansible.builtin.assert": {
                                "that": [
                                    f"_rke2_srv_eff.profile | default('') == '{expected}'"
                                ]
                            },
                        },
                    ],
                }
                playbook = yaml.safe_dump([play])
                with tempfile.TemporaryDirectory() as temporary_directory:
                    playbook_path = os.path.join(temporary_directory, "playbook.yml")
                    with open(playbook_path, "w", encoding="utf-8") as playbook_file:
                        playbook_file.write(playbook)
                    command = [
                        "ansible-playbook",
                        "-i",
                        "localhost,",
                        "--connection=local",
                        playbook_path,
                    ]
                    if extra_vars:
                        import json

                        command += ["--extra-vars", json.dumps(extra_vars)]
                    environment = os.environ.copy()
                    environment["ANSIBLE_LOCAL_TEMP"] = os.path.join(
                        temporary_directory, "ansible-local"
                    )
                    result = subprocess.run(
                        command,
                        cwd=REPOSITORY_ROOT,
                        env=environment,
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                self.assertEqual(
                    result.returncode, 0, msg=result.stdout + result.stderr
                )

    def test_cni_is_wired_to_rke2_config_role(self):
        """The playbook must hand the top-level `cni` var to rke2_config as rke2_cni."""
        invocation = _role_invocation("rke2_config")
        include = invocation.get("ansible.builtin.include_role", {})
        self.assertEqual(include.get("name"), "rke2_config")
        self.assertEqual(include.get("apply", {}).get("tags"), ["config", "rke2"])

        config_vars = invocation["vars"]
        self.assertIn("rke2_cni", config_vars)
        self.assertEqual(config_vars["rke2_cni"], "{{ _rke2_playbook_cni }}")
        self.assertEqual(
            config_vars["rke2_additional_config"],
            "{{ _rke2_playbook_additional_config }}",
        )


if __name__ == "__main__":
    unittest.main()
