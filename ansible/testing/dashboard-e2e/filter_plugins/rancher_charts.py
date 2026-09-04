"""Jinja filters for picking a Rancher chart out of a Helm repository index.

The dashboard-e2e pipeline has to answer one question before it can deploy:
given a channel's ``index.yaml`` and a requested tag, which published chart is
that? The answer used to come from ``helm search`` piped into an embedded Python
script inside ``ansible.builtin.shell``. It is expressed here instead so the
ordering rules below are reviewable in one place and the playbook stays
declarative.

Two properties of the published charts drive the whole implementation:

* **Ordering a version is not string ordering.** ``2.13.10`` is newer than
  ``2.13.9``, ``rc10`` is newer than ``rc2``, and a final release is newer than
  its own release candidate. A lexical sort gets all three wrong.

* **A commit-named chart has no order at all.** The release team publishes head
  builds as ``X.Y.Z-<sha>-head``, and a sha is not a sequence: sorting one picks
  whichever commit has the highest hex digits. Only the ``created`` date in the
  index says which build is newest, which is what these filters use.
"""

from __future__ import annotations

import re

__metaclass__ = type

# X.Y, optionally .Z, optionally a pre-release remainder. Anchored, so anything
# that is not a version at all simply does not match and sorts lowest.
_VERSION = re.compile(r"^v?(\d+)\.(\d+)(?:\.(\d+))?(?:-(.*))?$")

# A pre-release that is a named stage and a number, such as "rc2" or "alpha14".
_STAGE = re.compile(r"^([a-z]+)\.?(\d+)$")

# A final release and nothing else: no pre-release remainder, no commit head.
_FINAL = re.compile(r"^\d+\.\d+\.\d+$")

# Where a stage sits on the release ladder. A final release outranks its own
# release candidate, and a candidate outranks an alpha. Anything else (a hotfix
# build, a commit head) is below all of them: it is a build off to one side, not
# a step towards the release.
_GA = 3
_STAGE_RANK = {"rc": 2, "alpha": 1}
_OTHER = 0


def _sort_key(version):
    """Position of one chart version on the release ladder, as a sortable tuple."""
    match = _VERSION.match(version or "")
    if not match:
        return (0, 0, 0, _OTHER, 0)

    major, minor, patch, pre = match.groups()
    numbers = (int(major), int(minor), int(patch or 0))

    if not pre:
        return numbers + (_GA, 0)

    stage = _STAGE.match(pre)
    if not stage:
        return numbers + (_OTHER, 0)

    name, number = stage.groups()
    return numbers + (_STAGE_RANK.get(name, _OTHER), int(number))


def _line_of(version):
    """The ``X.Y`` release line a version belongs to, or ``""``."""
    match = _VERSION.match(version or "")
    return "%s.%s" % (match.group(1), match.group(2)) if match else ""


def _on_line(versions, line):
    """Every version on one release line.

    The boundary is the point: ``2.1`` must not swallow ``2.15``, and ``2.12.5``
    must not swallow ``2.12.50``, so a match has to end at a separator.
    """
    boundary = re.compile(r"^v?%s([.-]|$)" % re.escape(line))
    return [v for v in versions if boundary.match(v or "")]


def _is_head(version):
    return (version or "").endswith("-head")


def _versions(charts):
    """Chart versions from index.yaml ``entries.rancher``."""
    return [c.get("version", "") for c in charts or [] if c.get("version")]


def _stamp(created):
    """``created`` trimmed to the minute.

    Head charts publish several times a day, so a date alone does not identify
    which build ran. The index carries nanoseconds, which is more precision
    than a report needs.
    """
    # Normalised on the separator rather than on "T": every index published
    # today quotes the value, so PyYAML hands back a string, but an unquoted
    # one parses to a datetime whose str() uses a space. Slicing on "T" alone
    # would silently drop the time in that case, and a head chart identified
    # only by its date is ambiguous, since several publish most days.
    text = str(created or "").replace("T", " ", 1)
    return text[:16] if " " in text else text[:10]


def rancher_chart_newest_head(charts):
    """The most recently published head chart, by index date.

    Empty when the charts carry no head build. Callers fall back to the release
    ladder in that case; a channel of releases has no head chart to choose.
    """
    heads = [c for c in charts or [] if _is_head(c.get("version", ""))]
    if not heads:
        return ""
    return max(heads, key=lambda c: (c.get("created") or "", c.get("version", "")))["version"]


def rancher_chart_select(charts, tag, shapes=None):
    """The chart version a request resolves to, or ``""`` when nothing matches.

    ``charts`` is ``entries.rancher`` from a Helm repository index. ``tag`` is
    what the caller asked for: ``head``, a branch head such as ``v2.15-head``, a
    line such as ``v2.15``, a patch such as ``2.14.3``, or one published chart
    named in full. ``shapes`` is the set of pre-release suffixes the channel
    selects for a line (``["-rc", "-alpha"]`` for the consolidated Prime
    channel), or empty for a channel where any release counts.

    A ``head`` request means "the newest thing this channel builds": the newest
    line, and then that line's newest build by date.

    Every other request names a line, and resolves to a release on it. A branch
    head tag names its line the same way a bare minor does: ``v2.15-head`` is
    the 2.15 branch, and the chart that pairs with it is that line's newest
    release, because the branch head image ships no chart of its own.

    Commit-named head charts are deliberately not eligible for a line request,
    because such a chart is a new identity on every commit: a fixed input
    resolving to one would deploy a different build on every run. Pin one in
    full to run it on purpose, which the exact match below allows.
    """
    versions = _versions(charts)
    if not versions:
        return ""

    clean = (tag or "").lstrip("v")

    if tag == "head":
        newest_line = max(
            (_line_of(v) for v in versions),
            key=lambda line: _sort_key(line or "0.0"),
        )
        on_line = [c for c in charts if _line_of(c.get("version", "")) == newest_line]
        return rancher_chart_newest_head(on_line) or max(
            (c["version"] for c in on_line), key=_sort_key, default=""
        )

    # A tag naming one published chart is taken as written, so an explicit pin is
    # never silently upgraded and the channel's shape filter cannot exclude it.
    if clean in versions:
        return clean

    line = _line_of(clean)
    if not line:
        return ""

    candidates = [v for v in _on_line(versions, line) if not _is_head(v)]
    if shapes:
        candidates = [v for v in candidates if any(s in v for s in shapes)]

    # A request more specific than the line narrows further, so "2.12.5" cannot
    # answer with a 2.12.6 release. A branch head tag is not more specific: it
    # names the line, so it keeps every release on it.
    if clean != line and not _is_head(clean):
        candidates = _on_line(candidates, clean)

    return max(candidates, key=_sort_key, default="")


def rancher_chart_line_versions(charts, tag, limit=3):
    """The newest few charts on the requested line, whatever shape they are.

    For the failure message: when a line is published but carries no release the
    bare "nothing matched" points away from the answer, because the version is
    sitting in the listing in a shape the channel does not select.
    """
    line = _line_of((tag or "").lstrip("v"))
    if not line:
        return []
    on_line = sorted(_on_line(_versions(charts), line), key=_sort_key)
    return on_line[-limit:]


def rancher_chart_prime_pick(index_result, tag, heads=False):
    """The newest chart for a line in one Prime channel, or ``{}``.

    Takes an ``ansible.builtin.uri`` result for a channel index, so the loop in
    resolve-channel.yml can map over its results directly. The channel name
    comes from the looped item, which the uri module records alongside.

    Releases and head builds are never mixed. With ``heads`` false this returns
    the newest release and ignores head charts, which is what a Prime row wants:
    a release stays put, while a commit-named chart is a new identity on every
    commit. With ``heads`` true it returns the newest head chart instead, which
    is the only Prime build a minor has before its first release. The caller
    asks for releases first and falls back, so the two never compete.

    Head charts are ordered by publication date rather than by version, because
    a commit sha carries no order: sorting one picks whichever commit has the
    highest hex rather than the most recent build.
    """
    charts = ((index_result or {}).get("content") or "")
    if not charts:
        return {}

    # Parsing is left to the caller's from_yaml in the playbook for a plain
    # index; here the content is already a string, so parse it once.
    import yaml  # noqa: PLC0415 - only needed on this path

    try:
        # "or []" as well as the default: a channel that publishes the key with
        # nothing under it parses as None, not as an empty list, and None is not
        # iterable. An index in that shape is rare but real for a channel that
        # has been emptied rather than removed.
        entries = ((yaml.safe_load(charts) or {}).get("entries") or {}).get("rancher") or []
    except yaml.YAMLError:
        return {}

    line = _line_of((tag or "").lstrip("v"))
    if not line:
        return {}

    candidates = [
        c for c in entries
        if c.get("version")
        and _is_head(c["version"]) == bool(heads)
        and _on_line([c["version"]], line)
    ]
    if not candidates:
        return {}

    if heads:
        best = max(candidates, key=lambda c: (c.get("created") or "", c["version"]))
    else:
        best = max(candidates, key=lambda c: _sort_key(c["version"]))
    channel = ((index_result.get("_channel") or {}).get("name") or "")
    return {
        "channel": channel,
        "version": best["version"],
        "created": _stamp(best.get("created")),
        "head": bool(heads),
    }


def rancher_chart_ga_pick(index_result, tag):
    """The newest final release for a minor in one channel, or ``{}``.

    Separate from ``rancher_chart_prime_pick`` because a post-release run asks a
    different question. "Newest Prime chart" walks the release ladder, so it
    answers with a candidate the moment the next patch opens: with 2.15.1
    shipped, a 2.15.2-alpha1 outranks it on patch and a row asking for 2.15
    would quietly deploy an alpha. Here only ``X.Y.Z`` counts, so the answer is
    always something that shipped.

    A tag naming a full version is honoured exactly, which lets a run pin the
    release it means to test rather than tracking whatever is newest.
    """
    content = ((index_result or {}).get("content") or "")
    if not content:
        return {}

    import yaml  # noqa: PLC0415 - only needed on this path

    try:
        entries = ((yaml.safe_load(content) or {}).get("entries") or {}).get("rancher") or []
    except yaml.YAMLError:
        return {}

    clean = (tag or "").lstrip("v")
    releases = [c for c in entries if _FINAL.match(c.get("version") or "")]

    if _FINAL.match(clean):
        exact = [c for c in releases if c["version"] == clean]
        if not exact:
            return {}
        best = exact[0]
    else:
        line = _line_of(clean)
        if not line:
            return {}
        on_line = [c for c in releases if _on_line([c["version"]], line)]
        if not on_line:
            return {}
        best = max(on_line, key=lambda c: _sort_key(c["version"]))

    return {
        "channel": ((index_result.get("_channel") or {}).get("name") or ""),
        "version": best["version"],
        "created": _stamp(best.get("created")),
        "head": False,
    }


def rancher_chart_best_pick(picks):
    """The highest release among per-channel picks, or ``{}``.

    Ordering is the release ladder, so a final release outranks its own
    candidate and a candidate outranks an alpha. That is what makes a line which
    has reached rc resolve to the rc while a line that has not still resolves to
    its newest alpha rather than failing.
    """
    real = [p for p in picks or [] if p and p.get("version")]
    if not real:
        return {}
    if all(p.get("head") for p in real):
        return max(real, key=lambda p: (p.get("created") or "", p["version"]))
    return max(real, key=lambda p: _sort_key(p["version"]))


def rancher_chart_line_patch(index_content, line):
    """The highest final-release patch a minor has in one channel index, or -1.

    Pre-releases and head builds do not count: the question is what shipped, so
    a candidate for a version that has not been released yet says nothing about
    whether the line is still publishing.
    """
    if not index_content:
        return -1

    import yaml  # noqa: PLC0415 - only needed on this path

    try:
        entries = ((yaml.safe_load(index_content) or {}).get("entries") or {}).get("rancher") or []
    except yaml.YAMLError:
        return -1

    best = -1
    for chart in entries:
        match = re.match(r"^(\d+)\.(\d+)\.(\d+)$", chart.get("version") or "")
        if match and f"{match.group(1)}.{match.group(2)}" == line:
            best = max(best, int(match.group(3)))
    return best


class FilterModule:
    """Chart selection filters for the dashboard-e2e pipeline."""

    def filters(self):
        return {
            "rancher_chart_select": rancher_chart_select,
            "rancher_chart_line_versions": rancher_chart_line_versions,
            "rancher_chart_prime_pick": rancher_chart_prime_pick,
            "rancher_chart_ga_pick": rancher_chart_ga_pick,
            "rancher_chart_best_pick": rancher_chart_best_pick,
            "rancher_chart_line_patch": rancher_chart_line_patch,
        }
