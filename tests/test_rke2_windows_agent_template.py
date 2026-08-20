"""Tests for the rke2_windows_agent role template."""

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
    "rke2_windows_agent",
    "templates",
    "config.yaml.j2",
)


def run_render_playbook(playbook_body: str) -> subprocess.CompletedProcess:
    """Render the Windows config template inside a throwaway localhost playbook."""
    with tempfile.TemporaryDirectory() as temporary_directory:
        playbook_path = os.path.join(temporary_directory, "playbook.yml")
        with open(playbook_path, "w", encoding="utf-8") as playbook_file:
            playbook_file.write(playbook_body)

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


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
class TestRKE2WindowsAgentTemplate(unittest.TestCase):
    def test_renders_join_config_with_labels(self):
        playbook = textwrap.dedent(
            f"""
            - name: Render RKE2 Windows agent config
              hosts: localhost
              gather_facts: false
              vars:
                kube_api_host: 10.0.1.1
                rke2_token: "K10abc::server:secret"
                rke2_windows_node_labels:
                  - environment=qa
                rke2_windows_node_ip: 10.0.1.3
                rke2_windows_additional_config:
                  kubelet-arg:
                    - v=4
              tasks:
                - name: Parse rendered configuration
                  ansible.builtin.set_fact:
                    rendered_config: "{{{{ lookup('ansible.builtin.template', '{TEMPLATE_PATH}') | from_yaml }}}}"

                - name: Verify the agent joins the cluster on the supervisor port
                  ansible.builtin.assert:
                    that:
                      - rendered_config['server'] == 'https://10.0.1.1:9345'
                      - rendered_config['token'] == 'K10abc::server:secret'
                      - rendered_config['node-ip'] == '10.0.1.3'
                      - "'role-worker=true' in rendered_config['node-label']"
                      - "'environment=qa' in rendered_config['node-label']"
                      - rendered_config['kubelet-arg'] == ['v=4']
            """
        )

        result = run_render_playbook(playbook)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_renders_without_optional_values(self):
        """Defaults only: no node-ip key, and role-worker=true still applied."""
        playbook = textwrap.dedent(
            f"""
            - name: Render minimal RKE2 Windows agent config
              hosts: localhost
              gather_facts: false
              vars:
                kube_api_host: 10.0.1.1
                rke2_token: "K10abc::server:secret"
                rke2_windows_node_labels: []
                rke2_windows_node_ip: ""
                rke2_windows_additional_config: {{}}
              tasks:
                - name: Parse rendered configuration
                  ansible.builtin.set_fact:
                    rendered_config: "{{{{ lookup('ansible.builtin.template', '{TEMPLATE_PATH}') | from_yaml }}}}"

                - name: Verify optional keys are omitted
                  ansible.builtin.assert:
                    that:
                      - "'node-ip' not in rendered_config"
                      - rendered_config['node-label'] == ['role-worker=true']
            """
        )

        result = run_render_playbook(playbook)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
