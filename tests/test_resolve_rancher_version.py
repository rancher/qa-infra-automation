"""Unit tests for scripts/resolve_rancher_version.py"""

import json
import os
import sys
import unittest
from io import StringIO
from contextlib import redirect_stdout, redirect_stderr

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from scripts.resolve_rancher_version import load_entries, main, select_version

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures")


def fixture_index():
    with open(os.path.join(FIXTURES_DIR, "rancher_chart_index.yaml")) as handle:
        return load_entries(handle.name)


class TestSelectVersion(unittest.TestCase):
    def setUp(self):
        self.entries = fixture_index()

    def test_latest_final_ignores_prerelease_head_and_marketplace_shapes(self):
        self.assertEqual(select_version(self.entries)["version"], "2.15.2")

    def test_line_selects_highest_patch_of_that_line(self):
        self.assertEqual(select_version(self.entries, line="2.14")["version"], "2.14.3")

    def test_line_accepts_v_prefix(self):
        self.assertEqual(select_version(self.entries, line="v2.14")["version"], "2.14.3")

    def test_line_without_final_returns_empty(self):
        # 2.16 has only head/rc builds; a fixed input must never resolve to a
        # build whose identity changes on every commit.
        self.assertEqual(select_version(self.entries, line="2.16"), {})

    def test_prerelease_flag_admits_rc_above_newest_final(self):
        # Without the flag the newest final wins; with it, an rc of a newer
        # line outranks the older final (pre-release channels).
        self.assertEqual(select_version(self.entries)["version"], "2.15.2")
        self.assertEqual(
            select_version(self.entries, include_prerelease=True)["version"],
            "2.16.0-rc2",
        )

    def test_prerelease_flag_prefers_final_on_same_line(self):
        self.assertEqual(
            select_version(self.entries, line="2.15", include_prerelease=True)["version"],
            "2.15.2",
        )

    def test_prerelease_flag_still_excludes_head(self):
        self.assertEqual(
            select_version(self.entries, line="2.16", include_prerelease=True)["version"],
            "2.16.0-rc2",
        )

    def test_unknown_line_returns_empty(self):
        self.assertEqual(select_version(self.entries, line="9.9"), {})


class TestMain(unittest.TestCase):
    def test_json_output_with_index_file(self):
        stdout = StringIO()
        with redirect_stdout(stdout):
            code = main(
                [
                    "--repo-url",
                    "https://releases.rancher.com/server-charts/latest",
                    "--index-file",
                    os.path.join(FIXTURES_DIR, "rancher_chart_index.yaml"),
                    "--line",
                    "2.14",
                ]
            )
        self.assertEqual(code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["chart_version"], "2.14.3")
        self.assertEqual(payload["image_tag"], "v2.14.3")

    def test_no_match_exits_nonzero_with_stderr_message(self):
        stdout, stderr = StringIO(), StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = main(
                [
                    "--repo-url",
                    "https://releases.rancher.com/server-charts/latest",
                    "--index-file",
                    os.path.join(FIXTURES_DIR, "rancher_chart_index.yaml"),
                    "--line",
                    "9.9",
                ]
            )
        self.assertEqual(code, 1)
        self.assertIn("9.9", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
