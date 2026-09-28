"""Every play that runs a role pausing transactional-update.timer keeps it off for the run."""

import os
import unittest

try:
    import yaml
except ImportError:  # pragma: no cover - pyyaml ships with ansible
    yaml = None


REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
PLAYBOOKS = (
    os.path.join(REPOSITORY_ROOT, "ansible", "rke2", "default", "rke2-playbook.yml"),
    os.path.join(REPOSITORY_ROOT, "ansible", "k3s", "default", "k3s-playbook.yml"),
)
# rke2_setup pauses the timer itself; rke2_install/k3s_install include suse_selinux_policy, which does too.
TIMER_ROLES = {"rke2_setup", "rke2_install", "k3s_install"}


def _roles_of_play(play):
    found = set()
    for role in play.get("roles", []) or []:
        found.add(role["role"] if isinstance(role, dict) else role)

    def walk(tasks):
        for task in tasks or []:
            include = task.get("include_role") or task.get("ansible.builtin.include_role") or {}
            if isinstance(include, dict) and include.get("name"):
                found.add(include["name"])
            for section in ("block", "rescue", "always"):
                walk(task.get(section))

    for section in ("pre_tasks", "tasks", "post_tasks"):
        walk(play.get(section))

    return found


@unittest.skipIf(yaml is None, "pyyaml is required")
class TestUpdateTimerStaysOffDuringRuns(unittest.TestCase):
    def test_timer_aware_plays_disable_the_timer(self):
        checked = 0
        for playbook in PLAYBOOKS:
            with open(playbook, encoding="utf-8") as playbook_file:
                plays = yaml.safe_load(playbook_file)
            for play in plays:
                if not _roles_of_play(play) & TIMER_ROLES:
                    continue
                checked += 1
                label = play.get("name") or f"hosts={play.get('hosts')}"
                self.assertIs(
                    (play.get("vars") or {}).get("suse_disable_update_timer"),
                    True,
                    f"{os.path.basename(playbook)}: play '{label}' must set suse_disable_update_timer: true",
                )
        self.assertGreaterEqual(checked, 4, "expected the rke2 setup/install and both k3s install plays")

    def test_roles_still_honour_the_switch(self):
        for role in ("rke2_setup", "suse_selinux_policy"):
            tasks = os.path.join(REPOSITORY_ROOT, "ansible", "roles", role, "tasks", "main.yml")
            with open(tasks, encoding="utf-8") as tasks_file:
                self.assertIn("suse_disable_update_timer", tasks_file.read(), role)


if __name__ == "__main__":
    unittest.main()
