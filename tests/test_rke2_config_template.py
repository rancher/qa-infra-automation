"""Tests for the rke2_config role template."""

import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

import yaml


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
TEMPLATE_PATH = os.path.join(
    REPOSITORY_ROOT,
    "ansible",
    "roles",
    "rke2_config",
    "templates",
    "config.yaml.j2",
)
ROLE_DEFAULTS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "rke2_config", "defaults", "main.yml"
)


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
class TestRKE2ConfigTemplate(unittest.TestCase):
    def _render_defaults(self, variables, checks):
        play_vars = {
            "rke2_node_role": "master",
            "node_roles": ["cp", "etcd"],
            "fqdn": "api.example.invalid",
            "kube_api_host": "192.0.2.10",
            "ansible_host": "192.0.2.10",
        }
        play = {
            "name": "Render real RKE2 role defaults",
            "hosts": "localhost",
            "connection": "local",
            "gather_facts": False,
            "vars_files": [ROLE_DEFAULTS_PATH],
            "vars": play_vars,
            "tasks": [
                {
                    "name": "Parse the real template output",
                    "ansible.builtin.set_fact": {
                        "rendered_config": "{{ lookup('ansible.builtin.template', '"
                        + TEMPLATE_PATH
                        + "') | from_yaml }}"
                    },
                },
                {
                    "name": "Verify the parsed values",
                    "ansible.builtin.assert": {"that": checks},
                },
            ],
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            playbook_path = os.path.join(temp_dir, "render.yml")
            with open(playbook_path, "w", encoding="utf-8") as playbook_file:
                yaml.safe_dump([play], playbook_file)
            environment = os.environ.copy()
            environment["ANSIBLE_LOCAL_TEMP"] = os.path.join(temp_dir, "ansible-local")
            result = subprocess.run(
                [
                    "ansible-playbook",
                    "-i",
                    "localhost,",
                    playbook_path,
                    "--extra-vars",
                    json.dumps(variables),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
                timeout=90,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_default_kubeconfig_mode_survives_yaml_parsing(self):
        self._render_defaults(
            {},
            [
                "rendered_config['write-kubeconfig-mode'] is string",
                "rendered_config['write-kubeconfig-mode'] == '0644'",
                "(rendered_config['write-kubeconfig-mode'] | int(base=8)) == 420",
                "'192.0.2.10' in rendered_config['tls-san']",
            ],
        )

    def test_join_tokens_remain_exact_strings_for_servers_and_agents(self):
        for node_role in ("master", "agent"):
            for token in ("00123", "no", "null", 'dummy: token # with "quotes"', "dummy\ntoken"):
                with self.subTest(node_role=node_role, token=token):
                    self._render_defaults(
                        {
                            "rke2_node_role": node_role,
                            "node_roles": ["worker"] if node_role == "agent" else ["cp", "etcd"],
                            "rke2_token": token,
                        },
                        [
                            "rendered_config['token'] is string",
                            "rendered_config['token'] == rke2_token",
                        ],
                    )

    def test_server_string_values_survive_yaml_parsing(self):
        self._render_defaults(
            {
                "rke2_server_config": {
                    "write-kubeconfig-mode": "0600",
                    "node-name": "00123",
                }
            },
            [
                "rendered_config['write-kubeconfig-mode'] == '0600'",
                "rendered_config['node-name'] == '00123'",
            ],
        )

    def test_agent_string_values_survive_yaml_parsing(self):
        self._render_defaults(
            {
                "rke2_node_role": "agent",
                "node_roles": ["worker"],
                "rke2_agent_config": {
                    "server": "https://192.0.2.10:9345",
                    "node-name": "no",
                },
            },
            [
                "rendered_config['node-name'] == 'no'",
                "rendered_config['server'] == 'https://192.0.2.10:9345'",
                "'write-kubeconfig-mode' not in rendered_config",
            ],
        )

    def test_additional_config_preserves_value_types(self):
        playbook = textwrap.dedent(
            f"""
            - name: Render RKE2 config
              hosts: localhost
              gather_facts: false
              vars:
                node_type: master
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
