"""Unit tests for scripts/check_collections.py"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from scripts.check_collections import (
    effective_versions,
    find_drift,
    parse_requirements,
)

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scripts", "check_collections.py")


class TestParseRequirements(unittest.TestCase):
    def test_parses_name_version_pairs(self):
        data = {
            "collections": [
                {"name": "kubernetes.core", "version": "6.5.0"},
                {"name": "cloud.terraform", "version": "4.0.0"},
            ]
        }
        self.assertEqual(
            parse_requirements(data),
            {"kubernetes.core": "6.5.0", "cloud.terraform": "4.0.0"},
        )

    def test_empty_or_missing_collections_key(self):
        self.assertEqual(parse_requirements({}), {})
        self.assertEqual(parse_requirements({"collections": []}), {})


class TestEffectiveVersions(unittest.TestCase):
    def test_first_search_path_wins(self):
        # Mirrors the pipeline image: pinned collections under the user path
        # must shadow the older distro/apk bundle in the system path.
        galaxy_list = {
            "/home/user/.ansible/collections/ansible_collections": {
                "kubernetes.core": {"version": "6.5.0"},
            },
            "/usr/lib/python3.13/site-packages/ansible_collections": {
                "kubernetes.core": {"version": "5.3.0"},
                "ansible.posix": {"version": "1.6.2"},
            },
        }
        self.assertEqual(
            effective_versions(galaxy_list),
            {"kubernetes.core": "6.5.0", "ansible.posix": "1.6.2"},
        )

    def test_development_marker_versions_pass_through(self):
        galaxy_list = {"p": {"ansible._protomatter": {"version": "*"}}}
        self.assertEqual(
            effective_versions(galaxy_list), {"ansible._protomatter": "*"}
        )


class TestFindDrift(unittest.TestCase):
    REQUIRED = {"kubernetes.core": "6.5.0", "cloud.terraform": "4.0.0"}

    def test_no_drift_when_all_pins_match(self):
        installed = {
            "kubernetes.core": "6.5.0",
            "cloud.terraform": "4.0.0",
            "community.general": "13.4.0",
        }
        self.assertEqual(find_drift(self.REQUIRED, installed), [])

    def test_reports_missing_collection(self):
        drift = find_drift(self.REQUIRED, {"kubernetes.core": "6.5.0"})
        self.assertEqual(drift, ["cloud.terraform: missing (want 4.0.0)"])

    def test_reports_version_mismatch(self):
        drift = find_drift(
            self.REQUIRED,
            {"kubernetes.core": "5.3.0", "cloud.terraform": "4.0.0"},
        )
        self.assertEqual(drift, ["kubernetes.core: found 5.3.0, want 6.5.0"])


class TestCli(unittest.TestCase):
    """End-to-end runs against a fake ansible-galaxy shim on PATH."""

    def run_cli(self, requirements_text, galaxy_json=None, shim_lines=None):
        with tempfile.TemporaryDirectory() as tmp:
            req_path = os.path.join(tmp, "requirements.yml")
            with open(req_path, "w") as f:
                f.write(requirements_text)
            shim = os.path.join(tmp, "ansible-galaxy")
            with open(shim, "w") as f:
                f.write("#!/bin/sh\n")
                if shim_lines is None:
                    f.write("printf '%s' '" + json.dumps(galaxy_json or {}) + "'\n")
                else:
                    f.write("\n".join(shim_lines) + "\n")
            os.chmod(shim, 0o755)
            env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"])
            return subprocess.run(
                [sys.executable, SCRIPT, "--requirements", req_path],
                capture_output=True,
                text=True,
                env=env,
            )

    def test_exit_zero_and_summary_when_pins_match(self):
        proc = self.run_cli(
            "collections:\n  - name: cloud.terraform\n    version: \"4.0.0\"\n",
            {"/usr/collections": {"cloud.terraform": {"version": "4.0.0"}}},
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Collections OK", proc.stdout)

    def test_exit_one_with_hint_when_collection_missing(self):
        proc = self.run_cli(
            "collections:\n  - name: cloud.terraform\n    version: \"4.0.0\"\n",
            {"/usr/collections": {"kubernetes.core": {"version": "6.5.0"}}},
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("cloud.terraform: missing (want 4.0.0)", proc.stderr)
        self.assertIn("make collections", proc.stderr)

    def test_exit_two_when_listing_unparsable(self):
        with tempfile.TemporaryDirectory() as tmp:
            req_path = os.path.join(tmp, "requirements.yml")
            with open(req_path, "w") as f:
                f.write("collections:\n  - name: cloud.terraform\n    version: \"4.0.0\"\n")
            shim = os.path.join(tmp, "ansible-galaxy")
            with open(shim, "w") as f:
                f.write("#!/bin/sh\necho 'not json'\n")
            os.chmod(shim, 0o755)
            env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"])
            proc = subprocess.run(
                [sys.executable, SCRIPT, "--requirements", req_path],
                capture_output=True,
                text=True,
                env=env,
            )
        self.assertEqual(proc.returncode, 2)
        self.assertIn("cannot parse", proc.stderr)

    def test_known_empty_listing_is_drift_not_undeterminable(self):
        # ansible-galaxy (core <= 2.19) exits 1 with this exact message when
        # no configured path holds any collection: that is a determinate
        # empty set, so pins must report as missing (exit 1), not exit 2.
        proc = self.run_cli(
            "collections:\n  - name: cloud.terraform\n    version: \"4.0.0\"\n",
            shim_lines=[
                "echo 'ERROR! - None of the provided paths were usable. "
                "Please specify a valid path with --collections-path' >&2",
                "exit 1",
            ],
        )
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("cloud.terraform: missing (want 4.0.0)", proc.stderr)
        self.assertIn("None of the provided paths were usable", proc.stderr)
        self.assertNotIn("undeterminable", proc.stderr)

    def test_other_listing_failure_exits_two(self):
        # Any other non-zero exit (config errors, permissions) means the
        # installed set is undeterminable: exit 2, never a normal drift run.
        proc = self.run_cli(
            "collections:\n  - name: cloud.terraform\n    version: \"4.0.0\"\n",
            shim_lines=[
                "echo 'ERROR! Invalid configuration file' >&2",
                "exit 1",
            ],
        )
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertIn("collection list failed", proc.stderr)
        self.assertNotIn("Collections OK", proc.stdout)


if __name__ == "__main__":
    unittest.main()
