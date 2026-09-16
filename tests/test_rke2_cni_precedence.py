"""Behavior tests for CNI precedence: role resolution + rendered config.yaml."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

try:
    import yaml
except ImportError:  # pragma: no cover - pyyaml ships with ansible
    yaml = None


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
ROLE_TASKS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "rke2_config", "tasks", "main.yml"
)
ROLE_DEFAULTS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "rke2_config", "defaults", "main.yml"
)
PLAYBOOK_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "rke2", "default", "rke2-playbook.yml"
)
TEMPLATE_PATH = os.path.join(
    REPOSITORY_ROOT,
    "ansible",
    "roles",
    "rke2_config",
    "templates",
    "config.yaml.j2",
)

BASE_VARS = {
    "rke2_node_role": "master",
    "node_roles": [],
    "rke2_server_config": {},
    "rke2_agent_config": {},
    "rke2_disable_components": [],
}

RENDER_TASKS = [
    {
        "name": "Render configuration",
        "ansible.builtin.set_fact": {
            "rendered_text": (
                "{{ lookup('ansible.builtin.template', '" + TEMPLATE_PATH + "') }}"
            ),
        },
    },
    {
        "name": "Parse configuration",
        "ansible.builtin.set_fact": {
            "rendered_config": "{{ rendered_text | from_yaml }}",
        },
    },
]


def _playbook_config_vars():
    """Return the rke2_config role vars from rke2-playbook.yml."""
    with open(PLAYBOOK_PATH, encoding="utf-8") as playbook_file:
        plays = yaml.safe_load(playbook_file)
    for play in plays:
        for task in play.get("tasks", []) or []:
            include = task.get("ansible.builtin.include_role", {})
            if include.get("name") == "rke2_config":
                return task["vars"]

    raise AssertionError("rke2_config include vars not found in rke2-playbook.yml")


def _playbook_config_input_task():
    """Return the playbook task that resolves legacy and preferred inputs."""
    with open(PLAYBOOK_PATH, encoding="utf-8") as playbook_file:
        plays = yaml.safe_load(playbook_file)
    for play in plays:
        for task in play.get("pre_tasks", []) or []:
            if task.get("name") == "Resolve RKE2 configuration inputs":
                task = dict(task)
                task.pop("tags", None)
                return task

    raise AssertionError("RKE2 configuration input resolver not found")


def _resolve_cni_task():
    """Return the role's real 'Resolve effective CNI' task."""
    with open(ROLE_TASKS_PATH, encoding="utf-8") as tasks_file:
        tasks = yaml.safe_load(tasks_file)
    for task in tasks:
        if task.get("name", "").startswith("Resolve effective CNI"):
            return task

    raise AssertionError("Resolve effective CNI task not found in rke2_config tasks")


def _cni_line_check(count):
    return f"(rendered_text | regex_findall('(?m)^cni:') | length) == {count}"


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook is required")
@unittest.skipIf(yaml is None, "pyyaml is required")
class TestCNIPrecedence(unittest.TestCase):
    """Respect the product default and preserve legacy explicit-CNI precedence."""

    # (case, vars-in-play, vars-via---extra-vars, expected cni or None, checks)
    CASES = [
        (
            "no cni at all -> key omitted",
            {"rke2_cni": ""},
            {},
            None,
            [],
        ),
        (
            "explicit cni only (vars.yaml or DTF CNI env)",
            {"rke2_cni": "cilium"},
            {},
            "cilium",
            [],
        ),
        (
            "explicit calico remains supported",
            {"rke2_cni": "calico"},
            {},
            "calico",
            [],
        ),
        (
            "explicit canal remains supported",
            {"rke2_cni": "canal"},
            {},
            "canal",
            [],
        ),
        (
            "additional config only, playbook empty cni",
            {"rke2_cni": ""},
            {"rke2_additional_config": {"cni": "calico", "profile": "cis"}},
            "calico",
            ["rendered_config['profile'] == 'cis'"],
        ),
        (
            # the DTF shape that broke: BOTH values arrive as --extra-vars,
            # which set_fact cannot override — exactly one cni: may render
            "both via extra-vars -> explicit wins, single key",
            {},
            {
                "rke2_cni": "cilium",
                "rke2_additional_config": {"cni": "calico", "profile": "cis"},
            },
            "cilium",
            ["rendered_config['profile'] == 'cis'"],
        ),
        (
            # Preserve the legacy precedence for callers that pass calico.
            "legacy calico + additional cni -> additional wins",
            {"rke2_cni": "calico"},
            {"rke2_additional_config": {"cni": "cilium"}},
            "cilium",
            [],
        ),
        (
            # previously documented pattern: cni inside rke2_server_config
            "server_config cni + legacy calico -> server_config wins, single key",
            {"rke2_cni": "calico", "rke2_server_config": {"cni": "cilium"}},
            {},
            "cilium",
            [],
        ),
        (
            "server_config cni loses to additional config",
            {"rke2_cni": "", "rke2_server_config": {"cni": "canal"}},
            {"rke2_additional_config": {"cni": "cilium"}},
            "cilium",
            [],
        ),
        (
            "server_config cni loses to explicit rke2_cni",
            {"rke2_cni": "cilium", "rke2_server_config": {"cni": "canal"}},
            {},
            "cilium",
            [],
        ),
    ]

    def _run(self, play, extra_vars=None):
        with tempfile.TemporaryDirectory() as temporary_directory:
            playbook_path = os.path.join(temporary_directory, "playbook.yml")
            with open(playbook_path, "w", encoding="utf-8") as playbook_file:
                playbook_file.write(yaml.safe_dump([play]))

            command = [
                "ansible-playbook",
                "-i",
                "localhost,",
                "--connection=local",
                playbook_path,
            ]
            if extra_vars:
                command += ["--extra-vars", json.dumps(extra_vars)]

            environment = os.environ.copy()
            environment["ANSIBLE_LOCAL_TEMP"] = os.path.join(
                temporary_directory, "ansible-local"
            )
            return subprocess.run(
                command,
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
                timeout=90,
            )

    def test_cni_precedence_renders_expected_config(self):
        resolve_task = _resolve_cni_task()

        for case, play_vars, extra_vars, expected, extra_checks in self.CASES:
            with self.subTest(case=case):
                if expected is None:
                    checks = [
                        "'cni' not in (rendered_config | default({}, true))",
                        _cni_line_check(0),
                    ]
                else:
                    checks = [
                        f"rendered_config['cni'] == '{expected}'",
                        _cni_line_check(1),
                    ]
                checks += extra_checks

                merged = dict(BASE_VARS)
                merged.setdefault("rke2_additional_config", {})
                merged.update(play_vars)
                play = {
                    "name": f"CNI precedence: {case}",
                    "hosts": "localhost",
                    "gather_facts": False,
                    "vars": merged,
                    "tasks": [
                        resolve_task,  # the role's real resolution, verbatim
                        *RENDER_TASKS,
                        {
                            "name": "Verify rendered cni",
                            "ansible.builtin.assert": {"that": checks},
                        },
                    ],
                }
                result = self._run(play, extra_vars=extra_vars)
                self.assertEqual(
                    result.returncode, 0, msg=result.stdout + result.stderr
                )

    def test_role_default_preserves_calico_for_direct_consumers(self):
        """Existing direct consumers must not silently change their CNI."""
        play = {
            "name": "Role default preserves Calico",
            "hosts": "localhost",
            "gather_facts": False,
            "vars_files": [ROLE_DEFAULTS_PATH],
            "vars": {
                **BASE_VARS,
                "fqdn": "api.example.invalid",
                "kube_api_host": "192.0.2.10",
                "ansible_host": "192.0.2.10",
            },
            "tasks": [
                _resolve_cni_task(),
                *RENDER_TASKS,
                {
                    "name": "Verify direct-role compatibility",
                    "ansible.builtin.assert": {
                        "that": [
                            "rendered_config['cni'] == 'calico'",
                            _cni_line_check(1),
                        ]
                    },
                },
            ],
        }
        result = self._run(play)
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_example_vars_do_not_force_calico(self):
        config_vars = _playbook_config_vars()
        play = {
            "name": "Example variables leave CNI to RKE2",
            "hosts": "localhost",
            "gather_facts": False,
            "vars_files": [
                os.path.join(
                    REPOSITORY_ROOT, "ansible", "rke2", "default", "vars.yaml.example"
                )
            ],
            "vars": dict(BASE_VARS),
            "tasks": [
                _playbook_config_input_task(),
                {
                    "name": "Bind actual playbook role parameters",
                    "ansible.builtin.set_fact": {
                        "rke2_cni": config_vars["rke2_cni"],
                        "rke2_additional_config": config_vars["rke2_additional_config"],
                    },
                },
                _resolve_cni_task(),
                *RENDER_TASKS,
                {
                    "name": "Verify example does not select a CNI",
                    "ansible.builtin.assert": {
                        "that": [
                            "'cni' not in rendered_config",
                            _cni_line_check(0),
                        ]
                    },
                },
            ],
        }
        result = self._run(play)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_server_flags_reach_config_through_playbook(self):
        """vars.yaml server_flags/worker_flags land in the rendered config."""
        config_vars = _playbook_config_vars()
        resolve_inputs = _playbook_config_input_task()
        resolve_task = _resolve_cni_task()
        bind_role_params = {
            "name": "Bind resolved playbook inputs to role parameters",
            "ansible.builtin.set_fact": {
                "rke2_cni": config_vars["rke2_cni"],
                "rke2_additional_config": config_vars["rke2_additional_config"],
            },
        }

        cases = [
            (
                "server node uses server_flags",
                {"rke2_node_role": "master", "node_roles": []},
                {"server_flags": "profile: cis\ncni: calico"},
                [
                    "rendered_config['cni'] == 'calico'",
                    "rendered_config['profile'] == 'cis'",
                    _cni_line_check(1),
                ],
            ),
            (
                "worker node uses worker_flags",
                {"rke2_node_role": "agent", "node_roles": ["worker"]},
                {"worker_flags": "profile: cis", "server_flags": "cni: calico"},
                [
                    "rendered_config['profile'] == 'cis'",
                    "'cni' not in (rendered_config | default({}, true))",
                    _cni_line_check(0),
                ],
            ),
        ]
        for case, facts, flags, checks in cases:
            with self.subTest(case=case):
                merged = dict(BASE_VARS)
                merged.update(facts)
                merged.update(flags)
                play = {
                    "name": f"server_flags contract: {case}",
                    "hosts": "localhost",
                    "gather_facts": False,
                    "vars": merged,
                    "tasks": [
                        resolve_inputs,
                        bind_role_params,
                        resolve_task,
                        *RENDER_TASKS,
                        {
                            "name": "Verify flags landed",
                            "ansible.builtin.assert": {"that": checks},
                        },
                    ],
                }
                result = self._run(play)
                self.assertEqual(
                    result.returncode, 0, msg=result.stdout + result.stderr
                )

    def test_playbook_preserves_legacy_and_preferred_inputs(self):
        """Role params must not shadow vars.yaml/group_vars compatibility inputs."""
        resolve_inputs = _playbook_config_input_task()
        cases = [
            (
                "legacy rke2_cni",
                {"rke2_cni": "cilium"},
                ["_rke2_playbook_cni == 'cilium'"],
            ),
            (
                "preferred cni",
                {"cni": "canal"},
                ["_rke2_playbook_cni == 'canal'"],
            ),
            (
                "legacy additional config wins over server flags",
                {
                    "rke2_additional_config": {"profile": "cis"},
                    "server_flags": "profile: default",
                },
                ["_rke2_playbook_additional_config.profile == 'cis'"],
            ),
            (
                "server flags remain the fallback",
                {"server_flags": "profile: cis"},
                ["_rke2_playbook_additional_config.profile == 'cis'"],
            ),
            (
                "worker flags remain the agent fallback",
                {
                    "rke2_node_role": "agent",
                    "node_roles": ["worker"],
                    "worker_flags": "protect-kernel-defaults: true",
                },
                [
                    "_rke2_playbook_additional_config['protect-kernel-defaults'] == true"
                ],
            ),
        ]

        for case, variables, checks in cases:
            with self.subTest(case=case):
                play_vars = {
                    "rke2_node_role": "master",
                    "node_roles": [],
                }
                play_vars.update(variables)
                play = {
                    "name": f"Playbook input precedence: {case}",
                    "hosts": "localhost",
                    "gather_facts": False,
                    "vars": play_vars,
                    "tasks": [
                        resolve_inputs,
                        {
                            "name": "Verify resolved playbook inputs",
                            "ansible.builtin.assert": {"that": checks},
                        },
                    ],
                }
                result = self._run(play)
                self.assertEqual(
                    result.returncode, 0, msg=result.stdout + result.stderr
                )


if __name__ == "__main__":
    unittest.main()
