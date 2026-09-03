"""Tests for the generated cattle-config contract.

Every Rancher deploy playbook wired into ``make rancher`` / ``make all`` must:

  * default ``rancher_cattle_config_file`` (play vars) to a file rendered from
    ``ansible/_cattle-config.yaml.template`` into ``generated_config/`` (mode
    0600) and let the ``rancher_auth`` role resolve that same variable, so
    host/adminToken land in the file.
  * skip the render and target the caller's file verbatim when
    ``rancher_cattle_config_file`` is overridden (BYO ``CATTLE_TEST_CONFIG``);
    the file is enriched, never overwritten.

Bastion-hosted playbooks additionally fold the ui-plugin-charts mirror in when
the mirror local fact exists (i.e. a mirror is being served), including
``skipUIExtension: false``, into whatever file ``rancher_cattle_config_file``
resolves to. The default-ha playbook (localhost, online) must not reference
the airgap mirror fact at all.
"""

import base64
import os
import re
import unittest

import jinja2
import yaml

try:
    from ansible.plugins.filter.core import combine
except ImportError:  # pragma: no cover - ansible ships with the repo toolchain
    combine = None

REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
TEMPLATE_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "_cattle-config.yaml.template")
GITIGNORE_PATH = os.path.join(REPOSITORY_ROOT, ".gitignore")
ROLE_TASKS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "rancher_auth", "tasks", "main.yml")

DEFAULT_HA_PLAYBOOK = os.path.join(
    REPOSITORY_ROOT, "ansible", "rancher", "default-ha", "rancher-playbook.yml")
RKE2_SHARED_PLAYBOOK = os.path.join(
    REPOSITORY_ROOT, "ansible", "rke2", "shared", "playbooks", "deploy",
    "rancher-helm-deploy-playbook.yml")
K3S_SHARED_PLAYBOOK = os.path.join(
    REPOSITORY_ROOT, "ansible", "k3s", "shared", "playbooks", "deploy",
    "rancher-helm-deploy-playbook.yml")
RKE2_AIRGAP_PLAYBOOK = os.path.join(
    REPOSITORY_ROOT, "ansible", "rke2", "airgap", "playbooks", "deploy",
    "rancher-helm-deploy-playbook.yml")

BASTION_PLAYBOOKS = [
    ("rke2 shared", RKE2_SHARED_PLAYBOOK),
    ("k3s shared", K3S_SHARED_PLAYBOOK),
    ("rke2 airgap", RKE2_AIRGAP_PLAYBOOK),
]
ALL_PLAYBOOKS = [("default-ha", DEFAULT_HA_PLAYBOOK)] + BASTION_PLAYBOOKS

GENERATED_DEST_SUFFIX = os.path.join("generated_config", "cattle-config.yaml")
MIRROR_FACT_PATH = "/etc/ansible/facts.d/ui_plugin_mirror.fact"
GATE = "ui_mirror_fact_stat.stat.exists"


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
    env.filters["regex_replace"] = lambda v, p, r="": re.sub(p, r, v)
    env.filters["b64decode"] = lambda v: base64.b64decode(v).decode()
    env.filters["from_yaml"] = lambda v: yaml.safe_load(v)
    env.filters["from_json"] = lambda v: yaml.safe_load(v)
    return env.from_string(template).render(**variables)


def _iter_tasks(tasks):
    for task in tasks or []:
        yield task
        for key in ("block", "rescue", "always"):
            yield from _iter_tasks(task.get(key))


def _find_task(play, name):
    for task in _iter_tasks((play.get("tasks") or []) + (play.get("post_tasks") or [])):
        if isinstance(task, dict) and task.get("name") == name:
            return task
    raise AssertionError(f"task {name!r} not found")


def _load_play(path):
    with open(path, encoding="utf-8") as handle:
        return yaml.safe_load(handle)[0]


class TestBaseTemplate(unittest.TestCase):
    """The checked-in template must render to a valid cattle config base."""

    def test_renders_to_yaml_with_rancher_mapping(self):
        with open(TEMPLATE_PATH, encoding="utf-8") as handle:
            rendered = yaml.safe_load(_render(handle.read(), {}))
        self.assertIsInstance(rendered.get("rancher"), dict)

    def test_generated_output_is_gitignored(self):
        with open(GITIGNORE_PATH, encoding="utf-8") as handle:
            self.assertIn("generated_config/", handle.read().splitlines())


class TestGenerationWiring(unittest.TestCase):
    """Each make-wired deploy playbook generates and enriches the same file."""

    def test_template_task_renders_base_before_auth(self):
        for label, path in ALL_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                render_task = _find_task(play, "Render cattle-config.yaml from the base template")
                template = render_task["ansible.builtin.template"]
                self.assertTrue(template["src"].endswith("_cattle-config.yaml.template"))
                self.assertEqual(template["dest"], "{{ cattle_config_generated }}")
                self.assertEqual(template["mode"], "0600")

                names = [t.get("name") for t in _iter_tasks(
                    (play.get("tasks") or []) + (play.get("post_tasks") or []))]
                self.assertLess(
                    names.index("Render cattle-config.yaml from the base template"),
                    names.index("Configure Rancher admin user and generate API token"))

    def test_cattle_config_file_defaults_at_play_scope(self):
        for label, path in ALL_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                self.assertEqual(play["vars"]["rancher_cattle_config_file"],
                                 "{{ cattle_config_generated }}")
                self.assertTrue(
                    play["vars"]["cattle_config_generated"].endswith(GENERATED_DEST_SUFFIX))
                # Pinned include vars would outrank play vars; the path must
                # flow to rancher_auth unshadowed so -e overrides work end to end.
                auth_task = _find_task(play, "Configure Rancher admin user and generate API token")
                self.assertNotIn("rancher_cattle_config_file", auth_task.get("vars") or {})
                self.assertEqual(auth_task.get("ansible.builtin.include_role", {}).get("name"),
                                 "rancher_auth")

    def test_byo_override_skips_render_and_never_overwrites(self):
        default = "/repo/generated_config/cattle-config.yaml"
        for label, path in ALL_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                render_task = _find_task(play, "Render cattle-config.yaml from the base template")
                variables = {"rancher_version": "v2.9.0",
                             "cattle_config_generated": default}
                self.assertEqual(_render("{{ %s }}" % render_task["when"],
                                         {**variables, "rancher_cattle_config_file": default}),
                                 "True")
                self.assertEqual(_render("{{ %s }}" % render_task["when"],
                                         {**variables, "rancher_cattle_config_file": "/ci/cattle-config.yaml"}),
                                 "False")

    def test_bastion_playbooks_delegate_writes_to_localhost(self):
        for label, path in BASTION_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                render_task = _find_task(play, "Render cattle-config.yaml from the base template")
                self.assertEqual(render_task["delegate_to"], "localhost")
                write_task = _find_task(play, "Write the updated cattle config")
                self.assertEqual(write_task["delegate_to"], "localhost")


class TestMirrorInjection(unittest.TestCase):
    """Bastion playbooks fold the mirror in exactly when it is being served."""

    def test_injection_is_gated_on_fact_existence(self):
        for label, path in BASTION_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                stat_task = _find_task(play, "Check for the ui-plugin-charts mirror fact on the bastion")
                self.assertEqual(stat_task["ansible.builtin.stat"]["path"], MIRROR_FACT_PATH)
                self.assertEqual(stat_task["register"], "ui_mirror_fact_stat")
                inject_task = _find_task(
                    play, "Inject bastion ui-plugin-charts mirror into the cattle config")
                self.assertEqual(inject_task.get("when"), GATE)

    def test_fact_slurped_from_bastion_not_delegated(self):
        # The play itself runs on the bastion; the fact read must not delegate.
        for label, path in BASTION_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                read_task = _find_task(play, "Read the mirror local fact")
                self.assertEqual(read_task["ansible.builtin.slurp"]["src"], MIRROR_FACT_PATH)
                self.assertNotIn("delegate_to", read_task)

    def test_missing_url_fails_the_run(self):
        for label, path in BASTION_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                fail_when = _find_task(play, "Fail when the mirror fact has no URL")["when"]
                for fact in ({}, {"branch": "main"}, {"url": ""}):
                    with self.subTest(fact=fact):
                        self.assertEqual(
                            _render("{{ %s }}" % fail_when, {"ui_mirror_fact": fact}),
                            "True")
                self.assertEqual(
                    _render("{{ %s }}" % fail_when,
                            {"ui_mirror_fact": {"url": "http://b:8080/x.git"}}),
                    "False")

    def test_merge_injects_url_branch_and_skip_ui_extension(self):
        for label, path in BASTION_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                merge_task = _find_task(play, "Merge neuvectorTest mirror settings into the cattle config")
                base = {"rancher": {"host": "rancher.example.com", "adminToken": "tok"},
                        "neuvectorTest": {"existing": True}}
                variables = {
                    "generated_cattle_config_raw": {
                        "content": base64.b64encode(yaml.safe_dump(base).encode()).decode()},
                    "ui_mirror_fact": {
                        "url": "http://10.0.1.5:8080/ui-plugin-charts.git",
                        "branch": "main"},
                }
                result = yaml.safe_load(_render(
                    merge_task["ansible.builtin.set_fact"]["generated_cattle_config"],
                    variables))
                self.assertEqual(result["rancher"], base["rancher"])
                self.assertEqual(result["neuvectorTest"], {
                    "existing": True,
                    "uiPluginChartsURL": "http://10.0.1.5:8080/ui-plugin-charts.git",
                    "uiPluginChartsBranch": "main",
                    "skipUIExtension": False,
                })

    def test_mirror_uses_the_overridable_config_path(self):
        for label, path in BASTION_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                read_task = _find_task(play, "Read the cattle config")
                self.assertEqual(read_task["ansible.builtin.slurp"]["src"],
                                 "{{ rancher_cattle_config_file }}")
                write_task = _find_task(play, "Write the updated cattle config")
                self.assertEqual(write_task["ansible.builtin.copy"]["dest"],
                                 "{{ rancher_cattle_config_file }}")
                self.assertIn("to_nice_yaml", write_task["ansible.builtin.copy"]["content"])
                self.assertEqual(write_task["ansible.builtin.copy"]["mode"], "0600")


class TestPublicHostInConfig(unittest.TestCase):
    """rancher.host must be the public DNS name in airgap-generated configs."""

    def test_bastion_playbooks_pass_the_public_hostname(self):
        for label, path in BASTION_PLAYBOOKS:
            with self.subTest(playbook=label):
                play = _load_play(path)
                auth_task = _find_task(play, "Configure Rancher admin user and generate API token")
                self.assertEqual(auth_task["vars"]["rancher_cattle_config_host"],
                                 "{{ rancher_public_hostname }}")

    def test_default_ha_derives_host_from_its_fqdn(self):
        play = _load_play(DEFAULT_HA_PLAYBOOK)
        auth_task = _find_task(play, "Configure Rancher admin user and generate API token")
        self.assertNotIn("rancher_cattle_config_host", auth_task["vars"])

    def test_role_prefers_explicit_host_and_falls_back_to_the_url(self):
        with open(ROLE_TASKS_PATH, encoding="utf-8") as handle:
            role_play = yaml.safe_load(handle)
        task = _find_task({"tasks": role_play}, "Update cattle config with admin token")
        template = task["ansible.builtin.set_fact"]["cattle_config_updated"]

        common = {"cattle_config": {"rancher": {}},
                  "rancher_api_token": "token-x:y",
                  "rancher_url_normalized": "https://ag-internal.example.com"}
        overridden = yaml.safe_load(_render(template, {
            **common, "rancher_cattle_config_host": "ag.example.com"}))
        self.assertEqual(overridden["rancher"]["host"], "ag.example.com")

        derived = yaml.safe_load(_render(template, {
            **common, "rancher_cattle_config_host": ""}))
        self.assertEqual(derived["rancher"]["host"], "ag-internal.example.com")


class TestDefaultHaHasNoMirrorWiring(unittest.TestCase):
    """The online (localhost) playbook must not touch the airgap mirror fact."""

    def test_no_mirror_references(self):
        with open(DEFAULT_HA_PLAYBOOK, encoding="utf-8") as handle:
            text = handle.read()
        self.assertNotIn("ui_plugin_mirror", text)
        self.assertNotIn("facts.d", text)


if __name__ == "__main__":
    unittest.main()
