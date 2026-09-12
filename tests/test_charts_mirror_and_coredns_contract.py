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


def _plays(path):
    with open(path) as fh:
        return yaml.safe_load(fh)


def _walk(node):
    """Yield every mapping in a task tree, descending into blocks and loops."""
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk(value)

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
        task = _require(
            self.tasks, "Persist mirror URL, branch, and ClusterRepo name as an Ansible local fact"
        )
        content = task["ansible.builtin.copy"]["content"]
        self.assertIn("charts_mirror_served_branch", content)
        self.assertNotIn("'branch': charts_mirror_branch}", content)
        # The deploy invocation reads charts_mirror_fact.clusterrepo; omitting
        # it here silently discards a charts_mirror_clusterrepo override.
        self.assertIn("'clusterrepo': charts_mirror_clusterrepo", content)

    def test_fact_is_persisted_only_after_the_url_is_verified(self):
        # The deploy treats the fact's presence as proof the mirror is live;
        # writing it before flush_handlers/ls-remote would repoint the catalog
        # at a dead endpoint when either step fails.
        outer = _require(self.tasks, "Mirror rancher-charts on the bastion")
        names = [t.get("name") for t in outer["block"]]
        self.assertLess(
            names.index("Verify the mirror answers smart-HTTP on the published URL"),
            names.index("Persist mirror URL, branch, and ClusterRepo name as an Ansible local fact"),
            "the fact must be persisted after the smart-HTTP verification",
        )

    def test_served_branch_applies_settled_suffix_conditionally(self):
        task = _require(self.tasks, "Compute the branch consumers clone")
        expr = task["ansible.builtin.set_fact"]["charts_mirror_served_branch"].strip()
        self.assertIn("charts_mirror_settled_suffix", expr)
        self.assertIn("charts_mirror_serve_settled", expr)

    def test_default_branch_derives_from_rancher_minor(self):
        default = self.defaults["charts_mirror_branch"]
        self.assertIn("rancher_image_tag", default)
        self.assertIn("release-v", default)

    def test_fetch_refspec_is_reapplied_on_reruns(self):
        # Bootstrap must not own the refspec: a repo bootstrapped for one
        # Rancher minor keeps fetching only that branch after a branch change,
        # so the refspec task has to run on every invocation, before the fetch.
        refspec = _require(self.tasks, "Scope the fetch refspec to the requested branch")
        self.assertNotIn("when", refspec, "the fetch refspec must run unconditionally")
        outer = _require(self.tasks, "Mirror rancher-charts on the bastion")
        names = [t.get("name") for t in outer["block"]]
        self.assertLess(
            names.index("Configure the upstream remote"),
            names.index("Fetch the mirrored branch (initial or refresh)"),
            "the remote must be configured before the fetch runs",
        )
        self.assertLess(
            names.index("Scope the fetch refspec to the requested branch"),
            names.index("Fetch the mirrored branch (initial or refresh)"),
            "the refspec must be set before the fetch runs",
        )

    def test_remote_configuration_recovers_partial_bootstrap(self):
        # An interrupted first run can leave the bare repo without the origin
        # remote; a bootstrap-gated remote config would skip forever while the
        # fetch fails with "no such remote", so it must run on every pass.
        remote = _require(self.tasks, "Configure the upstream remote")
        self.assertNotIn("when", remote, "remote configuration must run unconditionally")
        self.assertIn("already exists", remote["failed_when"])

    def test_fetch_is_time_bounded(self):
        # A stalled connection to git.rancher.io would otherwise hang the
        # whole pipeline indefinitely; the command module has no timeout
        # parameter, so the fetch must be wrapped in coreutils timeout.
        fetch = _require(self.tasks, "Fetch the mirrored branch (initial or refresh)")
        argv = fetch["ansible.builtin.command"]["argv"]
        self.assertEqual(argv[0], "timeout")
        self.assertIn("charts_mirror_fetch_timeout", argv[1])

    def test_reused_vhost_must_match_listener_port(self):
        port_fail = _require(
            self.tasks, "Fail when the existing vhost listens on a different port"
        )
        when = port_fail["when"]
        self.assertIn("charts_mirror_existing_listen", when)
        self.assertIn("charts_mirror_port | string", when)

    def test_reused_vhost_must_match_git_root(self):
        root_fail = _require(self.tasks, "Fail when the git roots differ")
        when = root_fail["when"]
        self.assertIn("charts_mirror_existing_root", when)
        self.assertIn("charts_mirror_parent", when)

    def test_reuse_rejects_duplicate_vhost_confs(self):
        # Two enabled confs each carry a Listen on the shared port; Apache
        # refuses to restart, so the role must fail loudly instead.
        _require(self.tasks, "Fail when both mirror vhosts are enabled")

    def test_safe_directory_is_scoped_to_the_mirror_not_a_wildcard(self):
        # A system-wide '*' disables git's ownership protection for every
        # repository on the bastion; only the mirror path needs to be safe.
        permit = _require(self.tasks, "Permit git-http-backend to serve the root-owned mirror")
        module = permit["ansible.builtin.command"]
        cmd = module["cmd"] if isinstance(module, dict) else module
        self.assertIn("safe.directory {{ charts_mirror_dest }}", cmd)
        self.assertNotIn("'*'", cmd)
        retire = _require(
            self.tasks, "Retire the blanket safe.directory wildcard this role used to set"
        )
        self.assertEqual(retire["ansible.builtin.command"]["argv"][-1], "\\*")

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

    def test_reuse_validates_git_root_before_publishing(self):
        root_fail = _require(self.tasks, "Fail when the git roots differ")
        when = root_fail["when"]
        self.assertIn("ui_plugin_existing_root", when)
        self.assertIn("ui_plugin_mirror_parent", when)

    def test_reuse_validates_listener_port_before_publishing(self):
        port_fail = _require(self.tasks, "Fail when the ports differ")
        when = port_fail["when"]
        self.assertIn("ui_plugin_existing_listen", when)
        self.assertIn("ui_plugin_mirror_port | string", when)

    def test_reuse_rejects_duplicate_vhost_confs(self):
        _require(self.tasks, "Fail when both mirror vhosts are enabled")


    def test_safe_directory_is_scoped_to_the_mirror_not_a_wildcard(self):
        permit = _require(self.tasks, "Permit git-http-backend to serve the root-owned mirror")
        module = permit["ansible.builtin.command"]
        cmd = module["cmd"] if isinstance(module, dict) else module
        self.assertIn("safe.directory {{ ui_plugin_mirror_dest }}", cmd)
        self.assertNotIn("'*'", cmd)
        retire = _require(
            self.tasks, "Retire the blanket safe.directory wildcard this role used to set"
        )
        self.assertEqual(retire["ansible.builtin.command"]["argv"][-1], "\\*")

class TestDownstreamCoreDNSOverride(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks = _tasks(PLAYBOOK_PATH)

    def test_outer_block_gated_on_internal_lb(self):
        outer = _find(
            self.tasks,
            "Make the server-url hostname resolvable inside the downstream cluster",
        )
        self.assertIn("internal_lb_hostname", outer["when"])

    def test_inner_apply_is_idempotent_on_reruns(self):
        # Content equality (not hostname presence) gates the apply: a hostname
        # occurring anywhere in the Corefile would suppress the block forever
        # and pin the agent to a stale internal-LB address after it changes.
        inner = _require(self.tasks, "Apply the managed hosts override when it changed")
        self.assertEqual(
            inner["when"],
            "downstream_corefile_managed != downstream_corefile_raw.stdout",
        )
        compute = _require(self.tasks, "Compute the Corefile with the managed hosts override")
        expr = compute["ansible.builtin.set_fact"]["downstream_corefile_managed"]
        self.assertIn("server-url-override begin", expr)
        self.assertIn("server-url-override end", expr)
        # The render strips any prior managed block before injecting, so a
        # changed IP replaces the mapping instead of accumulating entries.
        self.assertIn("regex_replace", expr)

    def test_override_pins_the_internal_lb_ip_to_the_server_url_hostname(self):
        # The hosts entry must pair the INTERNAL load balancer's IP (resolved
        # from internal_lb_hostname) with the hostname the agent validates as
        # server-url — the rancher_server_url override's host when set, else
        # the public fqdn — anything else leaves the cluster-agent unable to
        # validate server-url and the import stuck pending.
        compute = _require(self.tasks, "Compute the Corefile with the managed hosts override")
        expr = compute["ansible.builtin.set_fact"]["downstream_corefile_managed"]
        self.assertIn("downstream_internal_lb.stdout.split()[0]", expr)
        self.assertIn("downstream_server_url_host", expr)
        derive = _require(
            self.tasks, "Resolve the hostname the agent will validate as server-url"
        )
        derivation = derive["ansible.builtin.set_fact"]["downstream_server_url_host"]
        self.assertIn("rancher_server_url", derivation)
        self.assertIn("urlsplit('hostname')", derivation)
        self.assertIn("else fqdn", derivation)

    def test_play_var_prefers_the_public_hostname(self):
        # server-url is set to the PUBLIC hostname, so the CoreDNS override
        # must pin that same name. Generated inventories define
        # external_lb_hostname and NOT rancher_hostname, so the fallback chain
        # is rancher_hostname -> external_lb_hostname -> internal_lb_hostname;
        # an internal-first fallback would make the override a no-op and leave
        # the imported cluster pending on server-url validation.
        plays = _plays(PLAYBOOK_PATH)
        bastion_play = next(p for p in plays if p.get("hosts") == "bastion")
        self.assertEqual(
            bastion_play["vars"]["fqdn"],
            "{{ rancher_hostname | default(external_lb_hostname | default(internal_lb_hostname)) }}",
        )

    def test_all_kubectl_calls_carry_request_timeouts(self):
        # Descend into nested blocks and read FQCN module keys: the playbook
        # uses ansible.builtin.command/shell, so short-key lookups see nothing
        # and a top-level-only scan misses tasks inside blocks.
        checked_argv = checked_shell = 0
        for node in _walk(self.tasks):
            command = node.get("ansible.builtin.command") or node.get("command")
            if isinstance(command, dict):
                argv = command.get("argv") or []
                if argv and argv[0] == "kubectl":
                    self.assertIn(
                        "--request-timeout=30s", argv,
                        f"kubectl argv without --request-timeout in task: {node.get('name')}",
                    )
                    checked_argv += 1
            shell = node.get("ansible.builtin.shell") or node.get("shell")
            if shell and "kubectl" in str(shell):
                for line in str(shell).splitlines():
                    if line.strip().startswith("kubectl"):
                        self.assertIn(
                            "--request-timeout=30s", line,
                            f"kubectl shell line without --request-timeout in task: {node.get('name')}",
                        )
                        checked_shell += 1
        # The playbook must exercise both forms, or the contract silently
        # stopped guarding anything.
        self.assertGreater(checked_argv, 0, "no kubectl argv calls found to check")
        self.assertGreater(checked_shell, 0, "no kubectl shell calls found to check")


class TestDownstreamChartsCatalogRepoint(unittest.TestCase):
    """The downstream cluster's own rancher-charts catalog must follow the mirror.

    The agent's catalog stack seeds a downstream ClusterRepo pointing at
    git.rancher.io, unreachable in the airgap; installs issued through the
    Rancher cluster proxy then resolve against the stale bundled index and
    fail with "no chart version found" for any revision published after the
    snapshot. add-downstream-cluster.yml must repoint it at the bastion
    mirror and wait for the re-sync.
    """

    @classmethod
    def setUpClass(cls):
        cls.tasks = _tasks(PLAYBOOK_PATH)

    def test_block_gated_on_enable_charts_mirror(self):
        block = _find(
            self.tasks,
            "Repoint the downstream rancher-charts catalog at the bastion mirror",
        )
        self.assertEqual(
            block["when"], "enable_charts_mirror | default(false) | bool",
            "the downstream catalog repoint must be gated on enable_charts_mirror",
        )

    def test_reads_the_persisted_mirror_fact(self):
        slurp = _require(self.tasks, "Read the charts mirror local fact on the bastion")
        self.assertEqual(
            slurp["ansible.builtin.slurp"]["src"], "/etc/ansible/facts.d/charts_mirror.fact",
            "the repoint must take url/branch from the fact the mirror role persisted",
        )

    def test_seed_wait_reads_branch_not_just_repo(self):
        # The mirror URL is stable across Rancher upgrades while the served
        # branch moves, so a repo-only read cannot detect a stale branch.
        seed = _require(
            self.tasks, "Wait for the agent to seed the downstream rancher-charts ClusterRepo"
        )
        jsonpath = seed["ansible.builtin.command"]["argv"][-1]
        self.assertIn("{.spec.gitRepo}", jsonpath)
        self.assertIn("{.spec.gitBranch}", jsonpath)

    def test_patch_targets_downstream_clusterrepo_with_fact_values(self):
        patch = _require(self.tasks, "Patch the downstream ClusterRepo to the mirror")
        argv = patch["ansible.builtin.command"]["argv"]
        self.assertIn("clusterrepos.catalog.cattle.io", argv)
        self.assertIn("rancher-charts", argv)
        payload = argv[argv.index("-p") + 1]
        self.assertIn("charts_mirror_fact.url", payload)
        self.assertIn("charts_mirror_fact.branch", payload)
        # Idempotent on repo AND branch: a Rancher upgrade keeps the mirror
        # URL but moves the branch, so both comparisons gate the patch.
        when = patch["when"]
        self.assertIn("charts_mirror_fact.url", when)
        self.assertIn("charts_mirror_fact.branch", when)

    def test_sync_wait_asserts_mirror_url_and_commit(self):
        wait = _require(self.tasks, "Wait for the downstream catalog to re-sync from the mirror")
        argv = wait["ansible.builtin.command"]["argv"]
        self.assertIn("{.status.url}", argv[-1])
        self.assertIn("{.status.downloadTime}", argv[-1])
        until = wait["until"]
        self.assertIn("charts_mirror_fact.url", until)
        self.assertIn("downstream_charts_repo_synced.stdout", until)
        self.assertIn("> 0", until, "the wait must require a non-empty download timestamp")
        # A branch-only patch leaves status.url unchanged and an exact mirror
        # of the same branch state leaves the commit unchanged, so the wait
        # must require the downloadTime to move past the pre-patch baseline
        # whenever a patch actually ran (skipped patch == idempotent re-run).
        self.assertIn("downstream_charts_patch is skipped", until)
        self.assertIn("downstream_charts_pre_download", until)

if __name__ == "__main__":
    unittest.main()
