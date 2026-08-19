"""Tests for the rke2_config role template."""

import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
TEMPLATE_PATH = os.path.join(
    REPOSITORY_ROOT,
    "ansible",
    "roles",
    "rke2_config",
    "templates",
    "config.yaml.j2",
)


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
class TestRKE2ConfigTemplate(unittest.TestCase):
    def test_additional_config_preserves_value_types(self):
        playbook = textwrap.dedent(
            f"""
            - name: Render RKE2 config
              hosts: localhost
              gather_facts: false
              vars:
                rke2_node_role: master
                node_roles: []
                rke2_server_config: {{}}
                rke2_agent_config: {{}}
                rke2_disable_components: []
                rke2_additional_config:
                  plain-string: hello
                  datastore-endpoint: "postgres://user:p@ss#word@db:5432/rke2"
                  integer-value: 42
                  boolean-value: true
                  list-value:
                    - one
                    - two
                  mapping-value:
                    nested: value
              tasks:
                - name: Parse rendered configuration
                  ansible.builtin.set_fact:
                    rendered_config: "{{{{ lookup('ansible.builtin.template', '{TEMPLATE_PATH}') | from_yaml }}}}"

                - name: Verify additional configuration values
                  ansible.builtin.assert:
                    that:
                      - rendered_config['plain-string'] == 'hello'
                      - rendered_config['datastore-endpoint'] == 'postgres://user:p@ss#word@db:5432/rke2'
                      - rendered_config['integer-value'] == 42
                      - rendered_config['boolean-value'] == true
                      - rendered_config['list-value'] == ['one', 'two']
                      - rendered_config['mapping-value']['nested'] == 'value'
            """
        )

        with tempfile.TemporaryDirectory() as temporary_directory:
            playbook_path = os.path.join(temporary_directory, "playbook.yml")
            with open(playbook_path, "w", encoding="utf-8") as playbook_file:
                playbook_file.write(playbook)

            environment = os.environ.copy()
            environment["ANSIBLE_LOCAL_TEMP"] = os.path.join(
                temporary_directory, "ansible-local"
            )
            result = subprocess.run(
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

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
