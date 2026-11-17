import filecmp
import os
import unittest

MODULES = os.path.join(os.path.dirname(__file__), "..", "tofu", "aws", "modules")


class TestIPv6ModuleMatchesDualstack(unittest.TestCase):
    # modules/ipv6 is a path consumers source directly, so it stays a copy.
    def test_tf_files_are_identical(self):
        tests = [os.path.join("tests", n) for n in ("nlb_targets.tftest.hcl", "variables.tftest.hcl", os.path.join("fixtures", "test.pub"))]
        for name in ("main.tf", "variables.tf", "outputs.tf", "terraform.tf", *tests):
            self.assertTrue(
                filecmp.cmp(
                    os.path.join(MODULES, "dualstack", name),
                    os.path.join(MODULES, "ipv6", name),
                    shallow=False,
                ),
                f"modules/ipv6/{name} drifted from modules/dualstack/{name}",
            )


if __name__ == "__main__":
    unittest.main()
