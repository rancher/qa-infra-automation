#!/usr/bin/env python3
"""Canary check: has a chart revision admissible to the airgap matrix shipped yet?

The airgap combined-tests pipeline cannot run TestAlertingTestSuite on the
Rancher v2.15 / RKE2 v1.36 matrix until upstream publishes a
rancher-alerting-drivers revision whose index annotations admit those
versions (Rancher's catalog filterReleases hides every other revision from
GetLatestChartVersion, so the suite fails with "failed to find chart" before
any install runs — a chart gate, not a registry or test problem).

This script evaluates that gate WITHOUT deploying anything:

  1. Fetch the published index (charts.rancher.io) and find revisions of the
     chart whose ``catalog.cattle.io/rancher-version`` and
     ``catalog.cattle.io/kube-version`` annotations admit the pinned matrix.
  2. If one is published, confirm it also sits on the release branch the
     airgap charts mirror tracks (release-v2.15); the mirror serves that
     branch, so only revisions on it are installable by the pipeline.

Exit codes (canary semantics — the Jenkins job stays green while the gate is
closed and goes red the moment it opens):

  0  gate closed (nothing admissible published, or published but not yet on
     the release branch)
  1  gate OPEN — an admissible revision is published AND on the release
     branch; the combined job's GO_TEST_CASE can be widened
  2  poll error (network/parse) — surfaced as UNSTABLE by the Jenkinsfile,
     never silently green

Usage:
    python3 scripts/alerting_chart_gate.py \\
        --rancher-version v2.15.0 --k8s-version v1.36.2
"""

import argparse
import re
import sys
import time
import urllib.request

import yaml

PUBLISHED_INDEX_URL = "https://charts.rancher.io/index.yaml"
BRANCH_INDEX_BASE_URL = "https://raw.githubusercontent.com/rancher/charts"
RANCHER_VERSION_ANNOTATION = "catalog.cattle.io/rancher-version"
KUBE_VERSION_ANNOTATION = "catalog.cattle.io/kube-version"

WIDEN_INSTRUCTIONS = (
    "ACTION: widen airgap-rke2-combined-tests-pipeline GO_TEST_CASE to "
    "'-run TestMonitoringTestSuite|TestAlertingTestSuite' "
    "(JJB qa-airgap-rke2-combined-tests.yml) and run the combined job."
)


def parse_version(text):
    """Return a comparable tuple for a semver-ish version string.

    ``v2.15.0`` / ``2.15.0`` -> (2, 15, 0, "") and ``2.15.0-rc1`` /
    ``1.36.2+rke2r1`` -> (1, 36, 2, "rke2r1"-free: build metadata is dropped,
    prerelease kept). Returns None when unparseable.
    """
    match = re.fullmatch(
        r"v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?",
        text.strip(),
    )
    if not match:
        return None
    major, minor, patch, prerelease = match.groups()
    return (int(major), int(minor), int(patch), prerelease or "")


def compare_versions(left, right):
    """Compare two parsed versions; semver prerelease rules (release wins)."""
    if left[:3] != right[:3]:
        return -1 if left[:3] < right[:3] else 1
    lpre, rpre = left[3], right[3]
    if lpre == rpre:
        return 0
    if lpre == "":
        return 1  # release > any prerelease
    if rpre == "":
        return -1
    # Numeric identifiers sort below alphanumeric ones (semver rule 11);
    # a simple identifier-wise comparison covers the constraints in play.
    def identifiers(pre):
        return [int(p) if p.isdigit() else p for p in pre.split(".")]

    lids, rids = identifiers(lpre), identifiers(rpre)
    for lid, rid in zip(lids, rids):
        if lid != rid:
            mixed_types = isinstance(lid, int) is not isinstance(rid, int)
            if mixed_types:
                return -1 if isinstance(lid, int) else 1
            return -1 if lid < rid else 1
    return -1 if len(lids) < len(rids) else (0 if len(lids) == len(rids) else 1)


def parse_constraint(constraint):
    """Split a constraint string like '>= 2.14.0-0 < 2.15.0-0' into clauses.

    Returns a list of (operator, parsed-version) or None when any clause is
    unparseable.
    """
    clauses = []
    tokens = re.findall(r"(>=|<=|!=|=|>|<)\s*(\S+)", constraint)
    if not tokens:
        return None
    for operator, raw_version in tokens:
        parsed = parse_version(raw_version)
        if parsed is None:
            return None
        clauses.append((operator, parsed))
    return clauses


def version_satisfies(version, constraint):
    """Evaluate ``version`` against a constraint string (AND of clauses).

    Fail-open by design: an unparseable constraint evaluates True so a
    malformed annotation produces a false alarm (gate looks open) rather
    than silently hiding a usable revision — mirrors the intent of the
    canary.
    """
    if version is None:
        return False
    clauses = parse_constraint(constraint)
    if clauses is None:
        return True
    for operator, bound in clauses:
        outcome = compare_versions(version, bound)
        if operator == ">=" and outcome < 0:
            return False
        if operator == "<=" and outcome > 0:
            return False
        if operator == ">" and outcome <= 0:
            return False
        if operator == "<" and outcome >= 0:
            return False
        if operator == "=" and outcome != 0:
            return False
        if operator == "!=" and outcome == 0:
            return False
    return True


def admissible(entry, rancher_version, k8s_version):
    """True when the index entry's annotations admit the pinned matrix.

    Mirrors rancher's catalog filterReleases: annotations are optional; a
    missing annotation never excludes a revision.
    """
    annotations = entry.get("annotations") or {}
    rancher_constraint = annotations.get(RANCHER_VERSION_ANNOTATION)
    if rancher_constraint and not version_satisfies(rancher_version, rancher_constraint):
        return False, f"rancher-version {rancher_constraint}"
    kube_constraint = annotations.get(KUBE_VERSION_ANNOTATION)
    if kube_constraint and not version_satisfies(k8s_version, kube_constraint):
        return False, f"kube-version {kube_constraint}"
    return True, ""


def first_admissible(entries, rancher_version, k8s_version):
    """Newest admissible entry, plus human-readable exclusion reasons."""
    reasons, winner = [], None
    for entry in entries:  # index entries are newest-first
        ok, reason = admissible(entry, rancher_version, k8s_version)
        if ok:
            winner = entry
            break
        reasons.append(f"{entry.get('version', '?')} excluded by {reason}")
    return winner, reasons


def fetch_index(url, retries=3, timeout=30):
    last_error = None
    for attempt in range(retries):
        try:
            # charts.rancher.io rejects urllib's default User-Agent with 403;
            # identify the poll so it is blockable on their side too.
            request = urllib.request.Request(
                url, headers={"User-Agent": "qa-infra-alerting-chart-gate/1.0"}
            )
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return yaml.safe_load(response.read())
        except Exception as error:  # noqa: BLE001 - report and retry any fetch failure
            last_error = error
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"failed to fetch {url} after {retries} attempts: {last_error}")



def evaluate(published_entries, branch_entries, rancher_version, k8s_version):
    """Pure gate evaluation so the Jenkins entrypoint and tests share logic.

    Returns (exit_code, summary_lines).
    """
    lines = []
    matrix = "Rancher {}.{}.{} + k8s {}.{}.{}".format(
        *rancher_version[:3], *k8s_version[:3]
    )
    published, published_reasons = first_admissible(
        published_entries, rancher_version, k8s_version
    )
    newest = published_entries[0].get("version", "?") if published_entries else "none"
    lines.append(f"published revisions: {len(published_entries)} (newest {newest})")
    for reason in published_reasons[:5]:
        lines.append(f"  {reason}")

    if published is None:
        lines.append(f"GATE CLOSED: no published revision admits {matrix}")
        return 0, lines

    if branch_entries is None:
        lines.append(
            f"GATE OPEN (published only): {published.get('version')} admits {matrix} "
            "but the release-branch index could not be checked"
        )
        lines.append(WIDEN_INSTRUCTIONS)
        return 1, lines

    on_branch = any(
        entry.get("version") == published.get("version") for entry in branch_entries
    )
    if on_branch:
        lines.append(
            f"GATE OPEN: rancher chart revision {published.get('version')} admits "
            f"{matrix} and is on the release branch"
        )
        lines.append(WIDEN_INSTRUCTIONS)
        return 1, lines

    lines.append(
        f"GATE CLOSED (pending propagation): {published.get('version')} admits "
        f"{matrix} on the published index but is not on the release branch yet"
    )
    return 0, lines


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--chart", default="rancher-alerting-drivers")
    parser.add_argument("--rancher-version", default="v2.15.0")
    parser.add_argument(
        "--k8s-version",
        default="v1.36.2",
        help="kube version of the downstream cluster (v-prefix and +build tolerated)",
    )
    parser.add_argument("--published-index-url", default=PUBLISHED_INDEX_URL)
    parser.add_argument("--branch-index-base-url", default=BRANCH_INDEX_BASE_URL)
    parser.add_argument("--release-branch", default="release-v2.15")
    args = parser.parse_args()

    rancher_version = parse_version(args.rancher_version)
    k8s_version = parse_version(args.k8s_version)
    if rancher_version is None or k8s_version is None:
        print("error: unparseable --rancher-version/--k8s-version", file=sys.stderr)
        return 2

    try:
        published = fetch_index(args.published_index_url)
        published_entries = (published.get("entries") or {}).get(args.chart) or []
        if not published_entries:
            print(f"error: chart {args.chart} absent from published index")
            return 2
        branch_entries = None
        branch_url = f"{args.branch_index_base_url}/{args.release_branch}/index.yaml"
        try:
            branch = fetch_index(branch_url)
            branch_entries = (branch.get("entries") or {}).get(args.chart) or []
        except RuntimeError as error:
            print(f"warning: {error}", file=sys.stderr)
    except Exception as error:  # noqa: BLE001 - any poll failure exits 2
        print(f"error: {error}", file=sys.stderr)
        return 2

    exit_code, lines = evaluate(
        published_entries, branch_entries, rancher_version, k8s_version
    )
    print(f"chart gate: {args.chart} for {args.rancher_version}/{args.k8s_version}")
    for line in lines:
        print(line)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
