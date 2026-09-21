"""Contract tests for tofu/aws/modules/cluster_nodes bastion + airgap outputs.

The behavioural assertions live in the module's own ``tests/*.tftest.hcl``
(mocked providers, no AWS). This file wires them into the Python suite and adds
cheap static checks that run even without a ``tofu`` binary.
"""

import os
import re
import shutil
import subprocess
import unittest

REPOSITORY_ROOT = os.path.join(os.path.dirname(__file__), "..")
MODULE_DIR = os.path.join(REPOSITORY_ROOT, "tofu", "aws", "modules", "cluster_nodes")


def _read(name):
    with open(os.path.join(MODULE_DIR, name), encoding="utf-8") as handle:
        return handle.read()


class ClusterNodesAirgapContractStaticTests(unittest.TestCase):
    """Static checks on the module source (no tofu needed)."""

    def test_airgap_and_proxy_default_to_false(self):
        variables = _read("variables.tf")
        for name in ("airgap_setup", "proxy_setup"):
            block = re.search(r'variable "%s" \{(.*?)\n\}' % name, variables, re.S)
            self.assertIsNotNone(block, f"variable {name} missing")
            self.assertIn("type        = bool", block.group(1), name)
            self.assertIn("default     = false", block.group(1), name)

    def test_bastion_variable_is_optional_object(self):
        variables = _read("variables.tf")
        block = re.search(r'variable "bastion" \{(.*?)\n\}', variables, re.S)
        self.assertIsNotNone(block)
        self.assertIn("enabled       = optional(bool, false)", block.group(1))
        self.assertIn("default = {}", block.group(1))

    def test_schema_v2_fields_are_exported(self):
        outputs = _read("outputs.tf")
        for field in (
            "schema_version  = 2",
            "airgap          = var.airgap_setup",
            "run_id          = var.run_id",
            "qa_infra_sha    = var.qa_infra_sha",
            "instance_id = aws_instance.node[node.name].id",
            "private_ip  = aws_instance.node[node.name].private_ip",
            "bastion = local.bastion_enabled ?",
        ):
            self.assertIn(field, outputs, field)
        for output in ("bastion_public_dns", "bastion_public_ip", "bastion_private_ip"):
            self.assertIn(f'output "{output}"', outputs, output)

    def test_no_output_addresses_nodes_by_public_ip_only(self):
        """Every consumer-facing address goes through local.node_ip (private in airgap)."""
        outputs = _read("outputs.tf")
        self.assertNotIn("first_master_index].name].public_ip", outputs)
        main = _read("main.tf")
        self.assertNotIn('"${aws_instance.node[each.value.node].public_ip}/32"', main)
        self.assertIn("local.node_ip[keys(local.cp_nodes)[0]]", main)


@unittest.skipUnless(shutil.which("tofu"), "tofu binary not available")
class ClusterNodesAirgapContractTofuTests(unittest.TestCase):
    """Runs the module's mocked tofu tests (needs provider download on first run)."""

    def test_tofu_test_passes(self):
        init = subprocess.run(
            ["tofu", "init", "-backend=false", "-input=false", "-no-color"],
            cwd=MODULE_DIR, capture_output=True, text=True, check=False,
        )
        if init.returncode != 0:
            self.skipTest(f"tofu init failed (offline?): {init.stderr[-400:]}")
        result = subprocess.run(
            ["tofu", "test", "-no-color"],
            cwd=MODULE_DIR, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout[-3000:] + result.stderr[-1000:])
        self.assertIn('run "airgap_with_bastion"... pass', result.stdout)
        self.assertIn('run "airgap_requires_bastion"... pass', result.stdout)


if __name__ == "__main__":
    unittest.main()
