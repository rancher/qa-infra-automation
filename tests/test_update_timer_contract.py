"""Every play that runs a role pausing transactional-update.timer keeps it off for the run."""

import os
import unittest

try:
    import yaml
except ImportError:  # pragma: no cover - pyyaml ships with ansible
    yaml = None


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
ANSIBLE_ROOT = os.path.join(REPOSITORY_ROOT, "ansible")
ROLES_ROOT = os.path.join(ANSIBLE_ROOT, "roles")
# rke2_setup pauses the timer itself; rke2_install/k3s_install include suse_selinux_policy, which does too.
TIMER_ROLES = {"rke2_setup", "rke2_install", "k3s_install"}
GUARD_ROLE = "suse_update_timer"


def _role_sequence(play):
    """Role names in execution order: pre_tasks, roles, tasks (blocks flattened)."""
    seq = []

    def walk(tasks):
        for task in tasks or []:
            include = task.get("include_role") or task.get("ansible.builtin.include_role") or {}
            if isinstance(include, dict) and include.get("name"):
                seq.append(include["name"])
            for section in ("block", "rescue", "always"):
                walk(task.get(section))

    walk(play.get("pre_tasks"))
    for role in play.get("roles", []) or []:
        seq.append(role["role"] if isinstance(role, dict) else role)
    walk(play.get("tasks"))
    walk(play.get("post_tasks"))

    return seq


def _playbooks():
    for root, _dirs, files in os.walk(ANSIBLE_ROOT):
        if root.startswith(ROLES_ROOT):
            continue
        for name in files:
            if not name.endswith((".yml", ".yaml")):
                continue
            path = os.path.join(root, name)
            with open(path, encoding="utf-8") as handle:
                try:
                    doc = yaml.safe_load(handle)
                except yaml.YAMLError:
                    continue
            if isinstance(doc, list) and doc and all(isinstance(p, dict) and "hosts" in p for p in doc):
                yield path, doc


@unittest.skipIf(yaml is None, "pyyaml is required")
class TestUpdateTimerStaysOffDuringRuns(unittest.TestCase):
    def test_every_timer_aware_play_disables_and_stops_the_timer_first(self):
        checked = []
        for path, plays in _playbooks():
            for play in plays:
                seq = _role_sequence(play)
                timer_positions = [i for i, r in enumerate(seq) if r in TIMER_ROLES]
                if not timer_positions:
                    continue
                label = f"{os.path.relpath(path, REPOSITORY_ROOT)}: play '{play.get('name') or play.get('hosts')}'"
                checked.append(label)
                self.assertIs(
                    (play.get("vars") or {}).get("suse_disable_update_timer"), True,
                    f"{label} must set suse_disable_update_timer: true",
                )
                self.assertIn(GUARD_ROLE, seq, f"{label} must run {GUARD_ROLE}")
                self.assertLess(
                    seq.index(GUARD_ROLE), min(timer_positions),
                    f"{label} must run {GUARD_ROLE} before {sorted(set(seq[i] for i in timer_positions))}",
                )
        expected = {
            "ansible/rke2/default/rke2-playbook.yml: play 'Setup nodes - RKE2 prerequisites'",
            "ansible/rke2/default/rke2-playbook.yml: play 'Install RKE2 binaries'",
            "ansible/k3s/default/k3s-playbook.yml: play 'master'",
            "ansible/k3s/default/k3s-playbook.yml: play 'all'",
            "ansible/k3s/shared/playbooks/setup/setup-agent-nodes.yml: play 'Setup K3s Agent Nodes'",
        }
        self.assertTrue(expected <= set(checked), f"missing plays: {sorted(expected - set(checked))}")

    def test_guard_role_stops_and_disables_only_when_asked(self):
        tasks_path = os.path.join(ROLES_ROOT, GUARD_ROLE, "tasks", "main.yml")
        with open(tasks_path, encoding="utf-8") as handle:
            tasks = yaml.safe_load(handle)
        outer = tasks[0]
        self.assertIn("suse_disable_update_timer", outer["when"])
        stop = [t for t in outer["block"] if "ansible.builtin.systemd_service" in t][0]
        self.assertEqual(stop["ansible.builtin.systemd_service"]["name"], "transactional-update.timer")
        self.assertEqual(stop["ansible.builtin.systemd_service"]["state"], "stopped")
        self.assertIs(stop["ansible.builtin.systemd_service"]["enabled"], False)

    def test_pausing_roles_still_honour_the_switch(self):
        for role in ("rke2_setup", "suse_selinux_policy"):
            tasks = os.path.join(ROLES_ROOT, role, "tasks", "main.yml")
            with open(tasks, encoding="utf-8") as tasks_file:
                self.assertIn("suse_disable_update_timer", tasks_file.read(), role)


if __name__ == "__main__":
    unittest.main()
