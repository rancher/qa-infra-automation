"""Unit tests for scripts/alerting_chart_gate.py (the alerting chart-gate canary)."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from scripts.alerting_chart_gate import (
    admissible,
    compare_versions,
    evaluate,
    first_admissible,
    parse_constraint,
    parse_version,
    version_satisfies,
)


def entry(version, rancher=None, kube=None):
    annotations = {}
    if rancher:
        annotations["catalog.cattle.io/rancher-version"] = rancher
    if kube:
        annotations["catalog.cattle.io/kube-version"] = kube
    return {"version": version, "annotations": annotations}


class TestParseVersion(unittest.TestCase):
    def test_accepts_common_forms(self):
        self.assertEqual(parse_version("v2.15.0"), (2, 15, 0, ""))
        self.assertEqual(parse_version("2.14.3"), (2, 14, 3, ""))
        self.assertEqual(parse_version("v1.36.2+rke2r1"), (1, 36, 2, ""))
        self.assertEqual(parse_version("2.15.0-rc1"), (2, 15, 0, "rc1"))
        self.assertEqual(parse_version("2.15.0-0"), (2, 15, 0, "0"))

    def test_rejects_garbage(self):
        for bad in ["", "latest", "2.15", "v2.x.0"]:
            self.assertIsNone(parse_version(bad), bad)


class TestCompareVersions(unittest.TestCase):
    def test_release_beats_prerelease(self):
        release = parse_version("2.15.0")
        self.assertEqual(compare_versions(release, parse_version("2.15.0-0")), 1)
        self.assertEqual(compare_versions(parse_version("2.15.0-0"), release), -1)

    def test_prerelease_ordering_numeric_below_alphanumeric(self):
        self.assertEqual(compare_versions(parse_version("2.15.0-0"), parse_version("2.15.0-rc1")), -1)
        self.assertEqual(compare_versions(parse_version("2.15.0-1"), parse_version("2.15.0-0")), 1)


class TestVersionSatisfies(unittest.TestCase):
    def test_upper_bound_with_prerelease_floor_excludes_release(self):
        # The exact pattern the gate exists to detect: '< 2.15.0-0' hides
        # v2.15.0 from the filtered index (semver: release > prerelease).
        self.assertFalse(version_satisfies(parse_version("2.15.0"), ">= 2.14.0-0 < 2.15.0-0"))
        self.assertFalse(version_satisfies(parse_version("1.36.2"), ">= 1.33.0-0 < 1.36.0-0"))

    def test_admissible_matrix(self):
        self.assertTrue(version_satisfies(parse_version("2.14.9"), ">= 2.14.0-0 < 2.15.0-0"))
        self.assertTrue(version_satisfies(parse_version("1.35.6"), ">= 1.33.0-0 < 1.36.0-0"))
        self.assertTrue(version_satisfies(parse_version("1.36.2"), ">= 1.36.0-0 < 1.39.0-0"))

    def test_unparseable_constraint_fails_open(self):
        self.assertTrue(version_satisfies(parse_version("2.15.0"), "sometime next quarter"))
        self.assertIsNone(parse_constraint("nope"))


class TestAdmissible(unittest.TestCase):
    def test_both_annotations_must_admit(self):
        matrix_rancher, matrix_kube = parse_version("v2.15.0"), parse_version("v1.36.2")
        excluded = entry("109.0.0", rancher=">= 2.14.0-0 < 2.15.0-0", kube=">= 1.33.0-0 < 1.36.0-0")
        ok, reason = admissible(excluded, matrix_rancher, matrix_kube)
        self.assertFalse(ok)
        self.assertIn("rancher-version", reason)

        admitted = entry("110.0.0", rancher=">= 2.15.0-0 < 2.16.0-0", kube=">= 1.34.0-0 < 1.37.0-0")
        ok, _ = admissible(admitted, matrix_rancher, matrix_kube)
        self.assertTrue(ok)

    def test_missing_annotations_admit(self):
        ok, _ = admissible(entry("1.0.0"), parse_version("v2.15.0"), parse_version("v1.36.2"))
        self.assertTrue(ok)


class TestEvaluate(unittest.TestCase):
    RANCHER, KUBE = parse_version("v2.15.0"), parse_version("v1.36.2")

    def test_closed_when_nothing_admissible(self):
        published = [
            entry("109.0.0", rancher=">= 2.14.0-0 < 2.15.0-0", kube=">= 1.33.0-0 < 1.36.0-0"),
            entry("108.0.1", rancher=">= 2.13.0-0 < 2.14.0-0", kube=">= 1.32.0-0 < 1.35.0-0"),
        ]
        code, lines = evaluate(published, published, self.RANCHER, self.KUBE)
        self.assertEqual(code, 0)
        self.assertTrue(any("GATE CLOSED" in line for line in lines))

    def test_open_when_admissible_on_release_branch(self):
        published = [
            entry("110.0.0", rancher=">= 2.15.0-0 < 2.16.0-0", kube=">= 1.34.0-0 < 1.37.0-0"),
        ]
        code, lines = evaluate(published, published, self.RANCHER, self.KUBE)
        self.assertEqual(code, 1)
        self.assertTrue(any("GATE OPEN" in line and "release branch" in line for line in lines))
        self.assertTrue(any("GO_TEST_CASE" in line for line in lines))

    def test_pending_when_published_but_branch_lags(self):
        published = [
            entry("110.0.0", rancher=">= 2.15.0-0 < 2.16.0-0", kube=">= 1.34.0-0 < 1.37.0-0"),
        ]
        branch = [entry("109.0.0", rancher=">= 2.14.0-0 < 2.15.0-0", kube=">= 1.33.0-0 < 1.36.0-0")]
        code, lines = evaluate(published, branch, self.RANCHER, self.KUBE)
        self.assertEqual(code, 0)
        self.assertTrue(any("pending propagation" in line for line in lines))

    def test_open_without_branch_check_when_branch_unavailable(self):
        published = [
            entry("110.0.0", rancher=">= 2.15.0-0 < 2.16.0-0", kube=">= 1.34.0-0 < 1.37.0-0"),
        ]
        code, lines = evaluate(published, None, self.RANCHER, self.KUBE)
        self.assertEqual(code, 1)

    def test_first_admissible_takes_newest(self):
        published = [
            entry("109.0.0", rancher=">= 2.14.0-0 < 2.15.0-0"),
            entry("108.0.0", rancher=">= 2.15.0-0"),
        ]
        winner, _ = first_admissible(published, self.RANCHER, self.KUBE)
        self.assertEqual(winner["version"], "108.0.0")


if __name__ == "__main__":
    unittest.main()
