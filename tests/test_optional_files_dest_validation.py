import os
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = os.path.join(os.path.dirname(__file__), "..", "ansible")


def validate_task(path):
    """Return the 'Validate' assert task from either the include file or the inline play."""
    def walk(node):
        if isinstance(node, dict):
            if str(node.get("name", "")).startswith("Optional files | Validate"):
                yield node
            for v in node.values():
                yield from walk(v)
        elif isinstance(node, list):
            for v in node:
                yield from walk(v)
    with open(path) as f:
        return next(walk(yaml.safe_load(f)))


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook not installed")
class TestOptionalFilesDest(unittest.TestCase):
    FILES = ("tasks/rke2-cis-setup.yml", "rke2/default/rke2-playbook.yml")

    def _passes(self, path, entry):
        task = validate_task(os.path.join(ROOT, path))
        task = {**task, "loop": ["{{ entry }}"]}
        play = [{"hosts": "localhost", "gather_facts": False, "vars": {"entry": entry}, "tasks": [task]}]
        with tempfile.TemporaryDirectory() as tmp:
            pb = os.path.join(tmp, "pb.yml")
            with open(pb, "w") as f:
                yaml.safe_dump(play, f)
            return subprocess.run(["ansible-playbook", "-i", "localhost,", "-c", "local", pb],
                                  capture_output=True, text=True, timeout=120).returncode == 0

    def test_dest_must_be_absolute_and_free_of_dotdot(self):
        for path in self.FILES:
            self.assertTrue(self._passes(path, "/etc/rancher/rke2/psa.yaml,https://e.test/a.yaml"), path)
            self.assertTrue(self._passes(path, "/etc/a.yaml,https://e.test/a.yaml," + "a" * 64), path)
            for bad in ("etc/psa.yaml,https://e.test/a", "/etc/../root/x,https://e.test/a",
                        "/etc/rancher/..,https://e.test/a", "nocomma"):
                self.assertFalse(self._passes(path, bad), f"{path}: {bad}")


if __name__ == "__main__":
    unittest.main()
