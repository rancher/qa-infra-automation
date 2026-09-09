"""Tests for add-downstream-cluster.yml cattle-config injection contract (issue #189).

Contract under test:
  * With ``enable_ui_plugin_mirror`` off (default) the cattle-config rewrite is
    byte-identical to the pre-injection behavior: ``rancher.clusterName`` only.
  * With the gate on, ``neuvectorTest.uiPluginChartsURL`` (and ``uiPluginChartsBranch``
    when non-empty) are injected from the local fact the
    ``airgap_rke2_ui_plugin_mirror`` role persisted on the bastion, preserving any
    existing ``neuvectorTest`` keys.
  * The role persists ``url``/``branch`` as JSON at
    ``/etc/ansible/facts.d/ui_plugin_mirror.fact``.
"""

import json
import os
import unittest

import jinja2
import yaml

try:
    from ansible.plugins.filter.core import combine, to_nice_json
except ImportError:  # pragma: no cover - ansible ships with the repo toolchain
    combine = None
    to_nice_json = None

REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
PLAYBOOK_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "rke2", "airgap", "playbooks", "deploy",
    "add-downstream-cluster.yml",
)
ROLE_TASKS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "airgap_rke2_ui_plugin_mirror",
    "tasks", "main.yml",
)
GATE = "enable_ui_plugin_mirror | default(false) | bool"


def _ansible_bool(value):
    """Ansible's ``bool`` filter semantics."""
    if value is True or value is False:
        return value
    if value is None:
        return False
    return str(value).strip().lower() in ("yes", "on", "1", "true", 1) or value == 1


def _render(template, variables):
    env = jinja2.Environment()
    env.filters["combine"] = combine
    env.filters["bool"] = _ansible_bool
    if to_nice_json is not None:
        env.filters["to_nice_json"] = to_nice_json
    return env.from_string(template).render(**variables)


def _iter_tasks(tasks):
    for task in tasks or []:
        yield task
        for key in ("block", "rescue", "always"):
            yield from _iter_tasks(task.get(key))


def _find_task(play, name):
    for task in _iter_tasks(play.get("tasks")):
        if isinstance(task, dict) and task.get("name") == name:
            return task
    raise AssertionError(f"task {name!r} not found")


def _load_plays(path):
    with open(path, encoding="utf-8") as handle:
        return yaml.safe_load(handle)


class TestRoleFactPersistence(unittest.TestCase):
    """The role must persist the mirror URL/branch as a bastion local fact."""

    @classmethod
    def setUpClass(cls):
        tasks = _load_plays(ROLE_TASKS_PATH)[0]["block"]
        cls.tasks = list(_iter_tasks(tasks))

    def _task(self, name):
        for task in self.tasks:
            if task.get("name") == name:
                return task
        raise AssertionError(f"task {name!r} not found in role")

    def test_fact_file_written_under_factsd(self):
        task = self._task("Persist mirror URL and branch as an Ansible local fact")
        copy = task["ansible.builtin.copy"]
        self.assertEqual(copy["dest"], "/etc/ansible/facts.d/ui_plugin_mirror.fact")

    def test_fact_dir_created_first(self):
        task = self._task("Ensure /etc/ansible/facts.d exists on the bastion")
        self.assertEqual(task["ansible.builtin.file"]["state"], "directory")

    def test_fact_content_is_valid_json_with_url_and_branch(self):
        task = self._task("Persist mirror URL and branch as an Ansible local fact")
        template = task["ansible.builtin.copy"]["content"]
        rendered = _render(template, {
            "ui_plugin_mirror_url": "http://10.0.1.5:8080/ui-plugin-charts.git",
            "ui_plugin_mirror_branch": "dev-v2.12",
        })
        self.assertEqual(
            json.loads(rendered),
            {
                "url": "http://10.0.1.5:8080/ui-plugin-charts.git",
                "branch": "dev-v2.12",
            },
        )


class TestDownstreamInjection(unittest.TestCase):
    """add-downstream-cluster.yml must inject the mirror URL behind the opt-in gate."""

    @classmethod
    def setUpClass(cls):
        cls.play = _load_plays(PLAYBOOK_PATH)[0]
        cls.update_block = _find_task(
            cls.play, "Update cattle-config.yaml with downstream cluster name")
        cls.inject_task = _find_task(
            cls.play, "Inject bastion ui-plugin-charts mirror into neuvectorTest")

    def _render_chain(self, cattle_config, gate_on, fact=None):
        """Reproduce the playbook's set_fact chain with the real ansible combine.

        set_fact stores native dicts; Jinja's str output round-trips through
        yaml.safe_load to restore the type between the two templates.
        """
        variables = {
            "cattle_config": cattle_config,
            "cluster_name": "ansible-created-ab12cd34",
            "enable_ui_plugin_mirror": gate_on,
            "ui_plugin_mirror_fact": fact or {},
        }
        step = _find_task(self.play, "Update cattle config with downstream cluster name")
        updated = yaml.safe_load(_render(
            step["ansible.builtin.set_fact"]["cattle_config_updated"], variables))
        if _render("{{ %s }}" % GATE, variables) == "True":
            updated = _render(
                self.inject_task["ansible.builtin.set_fact"]["cattle_config_updated"],
                {**variables, "cattle_config_updated": updated})
        return yaml.safe_load(updated) if isinstance(updated, str) else updated

    def test_inject_task_is_gated_on_the_opt_in(self):
        self.assertEqual(self.inject_task.get("when"), GATE)
        self.assertEqual(
            _find_task(self.play, "Read ui-plugin-charts mirror fact from the bastion").get("when"),
            GATE)

    def test_fact_is_read_from_the_bastion(self):
        read_task = _find_task(self.play, "Read the mirror local fact on the bastion")
        self.assertEqual(read_task["ansible.builtin.slurp"]["src"],
                         "/etc/ansible/facts.d/ui_plugin_mirror.fact")
        self.assertEqual(read_task["delegate_to"], "{{ groups['bastion'][0] }}")

    def test_missing_url_fails_the_run(self):
        fail_when = _find_task(
            self.play, "Fail when the mirror fact is missing or has no URL")["when"]
        for fact in ({}, {"branch": "main"}, {"url": ""}):
            with self.subTest(fact=fact):
                self.assertEqual(
                    _render("{{ %s }}" % fail_when, {"ui_plugin_mirror_fact": fact}),
                    "True")

    def test_gate_off_is_byte_identical_to_cluster_name_only(self):
        base = {"rancher": {"host": "rancher.example.com"}, "neuvectorTest": {"skipUIExtension": False}}
        gate_off = self._render_chain(base, gate_on=False, fact={"url": "http://b:8080/x.git"})
        self.assertEqual(
            gate_off,
            {
                "rancher": {"host": "rancher.example.com",
                            "clusterName": "ansible-created-ab12cd34"},
                "neuvectorTest": {"skipUIExtension": False},
            },
        )
        # No neuvectorTest key in the source → none may appear in the output.
        self.assertNotIn(
            "neuvectorTest",
            self._render_chain({"rancher": {}}, gate_on=False,
                               fact={"url": "http://b:8080/x.git"}))

    def test_gate_on_injects_url_and_branch_preserving_existing_keys(self):
        base = {"rancher": {"host": "rancher.example.com"},
                "neuvectorTest": {"skipUIExtension": False}}
        result = self._render_chain(
            base, gate_on=True,
            fact={"url": "http://10.0.1.5:8080/ui-plugin-charts.git", "branch": "main"})
        self.assertEqual(result["neuvectorTest"], {
            "skipUIExtension": False,
            "uiPluginChartsURL": "http://10.0.1.5:8080/ui-plugin-charts.git",
            "uiPluginChartsBranch": "main",
        })
        self.assertEqual(result["rancher"]["clusterName"], "ansible-created-ab12cd34")

    def test_gate_on_without_neuvector_section_creates_it(self):
        result = self._render_chain(
            {"rancher": {}}, gate_on=True, fact={"url": "http://10.0.1.5:8080/ui-plugin-charts.git"})
        self.assertEqual(result["neuvectorTest"]["uiPluginChartsURL"],
                         "http://10.0.1.5:8080/ui-plugin-charts.git")

    def test_gate_on_empty_branch_omits_branch_key(self):
        result = self._render_chain(
            {"rancher": {}}, gate_on=True, fact={"url": "http://b:8080/x.git", "branch": ""})
        self.assertEqual(result["neuvectorTest"], {"uiPluginChartsURL": "http://b:8080/x.git"})


if __name__ == "__main__":
    unittest.main()
