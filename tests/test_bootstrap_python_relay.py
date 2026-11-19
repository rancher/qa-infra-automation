import os
import unittest

import yaml

PLAYBOOK = os.path.join(os.path.dirname(__file__), "..", "ansible", "rke2", "shared", "bootstrap-python.yml")


def tasks_by_name():
    with open(PLAYBOOK) as f:
        play = yaml.safe_load(f)[0]
    return play, {t["name"]: t for t in play["tasks"]}


class TestBootstrapPythonRelay(unittest.TestCase):
    def test_bastion_relay_stays_default_and_dualstack_is_opt_in(self):
        _, tasks = tasks_by_name()
        for name in ("Copy Python binary from localhost to bastion (airgap)",
                     "Copy Python binary from bastion to target nodes (airgap)"):
            self.assertIn("not dualstack_inventory", tasks[name]["when"])
            self.assertNotIn("'airgap_nodes' in groups", tasks[name]["when"])
        direct = tasks["Copy Python binary to target nodes (dualstack/ipv6)"]
        self.assertIn("dualstack_inventory", direct["when"])

    def test_no_bastion_scp_brackets_ipv6_hosts(self):
        _, tasks = tasks_by_name()
        shell = tasks["Copy Python binary directly to target nodes (default)"]["ansible.builtin.shell"]
        self.assertIn("'[' ~ ansible_host ~ ']'", shell)


if __name__ == "__main__":
    unittest.main()
