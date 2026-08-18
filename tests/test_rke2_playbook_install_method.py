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


def _role_vars(role_name):
    """Return the vars dict of the given role invocation in rke2-playbook.yml."""
    with open(PLAYBOOK_PATH, encoding="utf-8") as playbook_file:
        plays = yaml.safe_load(playbook_file)
    for play in plays:
        for role in play.get("roles", []):
            if isinstance(role, dict) and role.get("role") == role_name:
                if "vars" in role:
                    return role["vars"]

    raise AssertionError(f"role {role_name} with vars not found in rke2-playbook.yml")


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

    def test_cni_is_wired_to_rke2_config_role(self):
        """The playbook must hand the top-level `cni` var to rke2_config as rke2_cni."""
        config_vars = _role_vars("rke2_config")
        self.assertIn("rke2_cni", config_vars)
        self.assertEqual(config_vars["rke2_cni"], "{{ cni | default('') }}")


if __name__ == "__main__":
    unittest.main()
