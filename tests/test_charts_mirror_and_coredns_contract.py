"""Contract tests for the charts mirror role and the downstream CoreDNS override.

Covers the review feedback on the airgap charts work:

* ``airgap_rke2_charts_mirror`` persists ``url``/``branch`` as a local fact
  where ``branch`` is the SERVED branch (settled suffix applied when
  ``charts_mirror_serve_settled`` is on), the settled refresh is gated on the
  same flag, and the default branch derives from the deployed Rancher minor.
* ``add-downstream-cluster.yml`` installs the CoreDNS hosts override only
  when an internal load balancer is configured, keeps it idempotent on
  reruns, and bounds every kubectl invocation with ``--request-timeout``.
"""

import os
import unittest

import yaml

REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
ROLE_TASKS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "airgap_rke2_charts_mirror",
    "tasks", "main.yml",
)
ROLE_DEFAULTS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "airgap_rke2_charts_mirror",
    "defaults", "main.yml",
)
PLAYBOOK_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "rke2", "airgap", "playbooks", "deploy",
    "add-downstream-cluster.yml",
)
UI_ROLE_TASKS_PATH = os.path.join(
    REPOSITORY_ROOT, "ansible", "roles", "airgap_rke2_ui_plugin_mirror",
    "tasks", "main.yml",
)


def _tasks(path):
    with open(path) as fh:
        plays = yaml.safe_load(fh)
    if plays and isinstance(plays[0], dict) and "tasks" in plays[0]:
        tasks = []
        for play in plays:
            tasks.extend(play.get("tasks", []))
        return tasks
    return plays


def _find(tasks, name):
    for task in tasks:
        if task.get("name") == name:
            return task
        block = task.get("block")
        if block:
            found = _find(block, name)
            if found is not None:
                return found
    return None


def _require(tasks, name):
    task = _find(tasks, name)
    if task is None:
        raise AssertionError(f"task not found: {name}")
    return task


class TestChartsMirrorRole(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks = _tasks(ROLE_TASKS_PATH)
        with open(ROLE_DEFAULTS_PATH) as fh:
            cls.defaults = yaml.safe_load(fh)

    def test_settled_refresh_is_gated_on_the_flag(self):
        task = _require(self.tasks, "Refresh the settled branch")
        self.assertEqual(
            task["when"], "charts_mirror_serve_settled | bool",
            "settled refresh must be gated on charts_mirror_serve_settled",
        )

    def test_fact_persists_the_served_branch_not_the_source_branch(self):
        task = _require(self.tasks, "Persist mirror URL and branch as an Ansible local fact")
        content = task["ansible.builtin.copy"]["content"]
        self.assertIn("charts_mirror_served_branch", content)
        self.assertNotIn("'branch': charts_mirror_branch}", content)

    def test_served_branch_applies_settled_suffix_conditionally(self):
        task = _require(self.tasks, "Compute the branch consumers clone")
        expr = task["ansible.builtin.set_fact"]["charts_mirror_served_branch"].strip()
        self.assertIn("charts_mirror_settled_suffix", expr)
        self.assertIn("charts_mirror_serve_settled", expr)

    def test_default_branch_derives_from_rancher_minor(self):
        default = self.defaults["charts_mirror_branch"]
        self.assertIn("rancher_image_tag", default)
        self.assertIn("release-v", default)

    def test_lsremote_verifies_the_served_branch(self):
        task = _require(self.tasks, "Verify the mirror answers smart-HTTP on the published URL")
        self.assertIn("charts_mirror_served_branch", task["ansible.builtin.command"]["cmd"])


class TestUiPluginVhostCoexistence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks = _tasks(UI_ROLE_TASKS_PATH)

    def test_ui_vhost_install_skips_when_charts_vhost_exists(self):
        stat = _require(self.tasks, "Check for an existing charts-mirror git vhost")
        self.assertEqual(
            stat["ansible.builtin.stat"]["path"], "/etc/apache2/conf-enabled/charts-mirror.conf"
        )
        install = _require(self.tasks, "Install Apache smart-HTTP vhost for git-http-backend")
        self.assertEqual(install["when"], "not ui_plugin_charts_vhost.stat.exists")


class TestDownstreamCoreDNSOverride(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks = _tasks(PLAYBOOK_PATH)

    def test_outer_block_gated_on_internal_lb(self):
        outer = _find(
            self.tasks,
            "Make the public Rancher hostname resolvable inside the downstream cluster",
        )
        self.assertIn("internal_lb_hostname", outer["when"])

    def test_inner_apply_is_idempotent_on_reruns(self):
        inner = _require(self.tasks, "Apply the hosts override when absent")
        self.assertIn("fqdn not in downstream_corefile_raw.stdout", inner["when"])

    def test_override_uses_the_public_hostname(self):
        render = _find(
            self.tasks, "Render the Corefile with a hosts override for the public hostname"
        )
        content = render["ansible.builtin.copy"]["content"]
        self.assertIn("fqdn", content)
        self.assertNotIn("internal_lb_hostname }} '", content.replace("~ fqdn", ""))

    def test_all_kubectl_calls_carry_request_timeouts(self):
        def walk(node):
            if isinstance(node, dict):
                yield node
                for v in node.values():
                    yield from walk(v)
            elif isinstance(node, list):
                for v in node:
                    yield from walk(v)
        for task in self.tasks:
            blob = yaml.safe_dump(task)
            if "kubectl" in blob and "argv" in blob:
                argv = task.get("command", {}).get("argv", [])
                if argv and argv[0] == "kubectl":
                    self.assertIn(
                        "--request-timeout=30s", argv,
                        f"kubectl argv without --request-timeout in task: {task.get('name')}",
                    )
            shell = task.get("shell")
            if shell and "kubectl" in str(shell):
                for line in str(shell).splitlines():
                    if line.strip().startswith("kubectl"):
                        self.assertIn(
                            "--request-timeout=30s", line,
                            f"kubectl shell line without --request-timeout in task: {task.get('name')}",
                        )


if __name__ == "__main__":
    unittest.main()
