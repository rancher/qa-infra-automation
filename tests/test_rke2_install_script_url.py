"""Tests for the rke2_install role's install script URL selection."""

import os
import unittest

try:
    import yaml
except ImportError:  # pragma: no cover - pyyaml ships with ansible
    yaml = None

try:
    import jinja2
except ImportError:  # pragma: no cover - jinja2 ships with ansible
    jinja2 = None


ROLE_ROOT = os.path.join(
    os.path.dirname(__file__), "..", "ansible", "roles", "rke2_install"
)


def _defaults():
    with open(os.path.join(ROLE_ROOT, "defaults", "main.yml"), encoding="utf-8") as f:
        return yaml.safe_load(f)


def _select_url_task():
    with open(os.path.join(ROLE_ROOT, "tasks", "main.yml"), encoding="utf-8") as f:
        tasks = yaml.safe_load(f)
    for task in tasks:
        for sub in task.get("block", []) or []:
            fact = sub.get("ansible.builtin.set_fact", {})
            if "_rke2_script_url" in fact:
                return fact["_rke2_script_url"]
    raise AssertionError("_rke2_script_url set_fact not found in rke2_install tasks")


def _ternary(value, true_val, false_val):
    return true_val if value else false_val


def _render_url(**overrides):
    variables = dict(_defaults())
    variables.update(overrides)
    env = jinja2.Environment()
    env.filters["ternary"] = _ternary
    env.filters["bool"] = lambda v: str(v).lower() in ("true", "yes", "1")
    # defaults reference rke2_version inside the pinned template, render it first
    variables["rke2_install_script_versioned_url"] = env.from_string(
        variables["rke2_install_script_versioned_url"]
    ).render(**variables)
    return env.from_string(_select_url_task()).render(**variables)


@unittest.skipIf(yaml is None or jinja2 is None, "pyyaml and jinja2 are required")
class Rke2InstallScriptUrlTest(unittest.TestCase):
    def test_pinning_is_off_by_default(self):
        self.assertIs(_defaults()["rke2_install_script_pinned"], False)

    def test_versioned_install_uses_floating_script(self):
        # The official flow is get.rke2.io + INSTALL_RKE2_VERSION; the tag's install.sh
        # can predate OS mappings such as SL Micro 6.2 -> slemicro (rancher/rke2#9723).
        self.assertEqual(
            _render_url(rke2_version="v1.34.11+rke2r1"), "https://get.rke2.io"
        )

    def test_unversioned_install_uses_floating_script(self):
        self.assertEqual(_render_url(rke2_version=""), "https://get.rke2.io")

    def test_pinned_install_uses_tag_script(self):
        self.assertEqual(
            _render_url(rke2_version="v1.34.11+rke2r1", rke2_install_script_pinned=True),
            "https://raw.githubusercontent.com/rancher/rke2/v1.34.11+rke2r1/install.sh",
        )

    def test_pinned_without_version_falls_back_to_floating(self):
        self.assertEqual(
            _render_url(rke2_version="", rke2_install_script_pinned=True),
            "https://get.rke2.io",
        )


if __name__ == "__main__":
    unittest.main()
