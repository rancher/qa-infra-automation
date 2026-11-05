"""Tests for the rke2_windows_agent role template."""

import json
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


ROLE_PATH = os.path.join(REPOSITORY_ROOT, "ansible", "roles", "rke2_windows_agent")


def run_role_prerequisites(extra_vars: dict) -> subprocess.CompletedProcess:
    """Run the role against localhost; the prerequisite assert fails before any win_* task."""
    role_vars = {
        "kube_api_host": "10.0.1.1",
        "rke2_token": "tok",
        "cni": "calico",
        **extra_vars,
    }
    playbook = (
        "- hosts: localhost\n"
        "  gather_facts: false\n"
        f"  vars: {json.dumps(role_vars)}\n"
        f"  roles:\n    - role: {ROLE_PATH}\n"
    )
    return run_render_playbook(playbook)


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
class TestRKE2WindowsAgentPrerequisites(unittest.TestCase):
    def test_rejects_host_without_node_os(self):
        result = run_role_prerequisites({})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("node_os: windows", result.stdout + result.stderr)

    def test_rejects_reserved_additional_config_keys(self):
        result = run_role_prerequisites(
            {"node_os": "windows", "rke2_windows_additional_config": {"token": "x"}}
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("managed by this role", result.stdout + result.stderr)

    def test_rejects_unsupported_resolved_cni(self):
        result = run_role_prerequisites(
            {"node_os": "windows", "rke2_windows_cni": "canal"}
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("calico or flannel", result.stdout + result.stderr)


STANDALONE_PLAYBOOK = os.path.join(
    REPOSITORY_ROOT,
    "ansible", "rke2", "shared", "playbooks", "setup", "setup-windows-agent-nodes.yml",
)


def run_standalone_cni_gate(extra_vars: dict) -> subprocess.CompletedProcess:
    """Run the standalone playbook's first play against localhost as master."""
    with tempfile.TemporaryDirectory() as temporary_directory:
        inventory = os.path.join(temporary_directory, "inventory.ini")
        with open(inventory, "w", encoding="utf-8") as inventory_file:
            inventory_file.write(
                "[master]\nlocalhost ansible_connection=local\n"
                "[windows_workers]\nwin-0 ansible_host=203.0.113.1\n"
            )
        variables = {
            "kubernetes_version": "v1.34.2+rke2r1",
            "ansible_become": False,
            **extra_vars,
        }
        environment = os.environ.copy()
        environment["ANSIBLE_LOCAL_TEMP"] = os.path.join(temporary_directory, "tmp")
        return subprocess.run(
            ["ansible-playbook", "-i", inventory, STANDALONE_PLAYBOOK,
             "-e", json.dumps(variables), "--limit", "master"],
            cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True, check=False,
        )


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
class TestStandaloneWindowsPlaybookCniGate(unittest.TestCase):
    def test_rejects_canal_from_server_flags(self):
        result = run_standalone_cni_gate({"cni": "", "server_flags": "cni: canal"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Windows-capable effective CNI", result.stdout + result.stderr)

    def test_accepts_calico_from_server_flags(self):
        result = run_standalone_cni_gate({"cni": "", "server_flags": "cni: calico"})
        # The play later fails reading the node token; only the gate is under test.
        self.assertRegex(
            result.stdout,
            r"TASK \[Validate required variables\][^\n]*\n(?:ok|changed): \[localhost\]",
        )
        self.assertIn("Read cluster token from master", result.stdout)


def run_ready_check(kubectl_output: str, expected_node: str) -> subprocess.CompletedProcess:
    """Run the role's real readiness tasks against a stub kubectl on localhost."""
    with tempfile.TemporaryDirectory() as temporary_directory:
        kubectl = os.path.join(temporary_directory, "kubectl")
        with open(kubectl, "w", encoding="utf-8") as kubectl_file:
            kubectl_file.write("#!/bin/sh\ncat <<'OUT'\n" + kubectl_output + "\nOUT\n")
        os.chmod(kubectl, 0o755)
        inventory = os.path.join(temporary_directory, "inventory.ini")
        with open(inventory, "w", encoding="utf-8") as inventory_file:
            inventory_file.write(
                "[master]\nlocalhost ansible_connection=local "
                f"rke2_windows_node_name={expected_node}\n"
            )
        playbook = os.path.join(temporary_directory, "playbook.yml")
        with open(playbook, "w", encoding="utf-8") as playbook_file:
            playbook_file.write(
                textwrap.dedent(
                    """\
                    - hosts: master
                      gather_facts: false
                      tasks:
                        - ansible.builtin.include_role:
                            name: rke2_windows_agent
                            tasks_from: wait_for_nodes_ready
                          vars:
                            rke2_windows_wait_timeout: 15
                            rke2_windows_kubectl_path: "{{ kubectl_stub }}"
                    """
                )
            )
        environment = os.environ.copy()
        environment["ANSIBLE_LOCAL_TEMP"] = os.path.join(temporary_directory, "tmp")
        return subprocess.run(
            ["ansible-playbook", "-i", inventory, playbook,
             "-e", json.dumps({"kubectl_stub": kubectl, "ansible_become": False})],
            cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True, check=False,
        )


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
class TestWindowsReadinessByNodeIdentity(unittest.TestCase):
    def test_passes_when_target_node_is_ready(self):
        result = run_ready_check("old-win   True\nnew-win   True", "new-win")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_fails_when_only_an_older_windows_node_is_ready(self):
        result = run_ready_check("old-win   True", "new-win")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("new-win", result.stdout + result.stderr)

    def test_fails_when_target_node_is_not_ready(self):
        result = run_ready_check("old-win   True\nnew-win   False", "new-win")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
