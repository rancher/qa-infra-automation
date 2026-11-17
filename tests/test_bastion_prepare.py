"""bastion_prepare must pick the right container runtime path per OS family.

The role runs for real on localhost; only the package-manager, service, download
and stat modules are replaced by stubs that record what would have happened.
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

REPOSITORY_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ROLE_DIR = os.path.join(REPOSITORY_ROOT, "ansible", "roles", "bastion_prepare")
STUBBED = ("zypper", "apt", "package", "systemd_service", "get_url", "stat")

STUB = """#!/usr/bin/python
# WANT_JSON
import json, sys
args = json.load(open(sys.argv[1]))
args = {{k: v for k, v in args.items() if not k.startswith("_ansible")}}
with open({log!r}, "a") as handle:
    handle.write(json.dumps({{"module": {name!r}, "args": args}}) + "\\n")
result = {{"changed": False}}
if {name!r} == "stat":
    result["stat"] = {{"exists": {transactional!r} == "yes"}}
print(json.dumps(result))
"""


@unittest.skipIf(shutil.which("ansible-playbook") is None, "ansible-playbook is required")
class TestBastionPrepare(unittest.TestCase):
    def _run(self, os_family, transactional=False):
        with tempfile.TemporaryDirectory() as tmpdir:
            role = os.path.join(tmpdir, "roles", "bastion_prepare")
            shutil.copytree(ROLE_DIR, role)
            # FQCNs bypass the library path, and action plugins like package shadow
            # same-named modules, so rename each stubbed module to a unique stub.
            pattern = re.compile(r"ansible\.builtin\.(%s):" % "|".join(STUBBED))
            for name in os.listdir(os.path.join(role, "tasks")):
                path = os.path.join(role, "tasks", name)
                with open(path, encoding="utf-8") as handle:
                    text = pattern.sub(r"stub_\1:", handle.read())
                with open(path, "w", encoding="utf-8") as handle:
                    handle.write(text)
            library = os.path.join(tmpdir, "library")
            os.mkdir(library)
            log = os.path.join(tmpdir, "calls.jsonl")
            for name in STUBBED:
                with open(os.path.join(library, f"stub_{name}.py"), "w", encoding="utf-8") as handle:
                    handle.write(STUB.format(log=log, name=name, transactional="yes" if transactional else "no"))
            with open(os.path.join(tmpdir, "play.yml"), "w", encoding="utf-8") as handle:
                handle.write("- hosts: localhost\n  gather_facts: false\n  roles: [bastion_prepare]\n")
            facts = {"ansible_facts": {"os_family": os_family, "architecture": "x86_64"}}
            result = subprocess.run(
                ["ansible-playbook", "-i", "localhost,", "-c", "local", "play.yml", "-e", json.dumps(facts)],
                cwd=tmpdir,
                env=dict(os.environ, ANSIBLE_LIBRARY=library, ANSIBLE_ROLES_PATH=os.path.join(tmpdir, "roles")),
                capture_output=True,
                text=True,
                check=False,
                timeout=120,
            )
            calls = []
            if os.path.exists(log):
                with open(log, encoding="utf-8") as handle:
                    calls = [json.loads(line) for line in handle]
        installed = [c["args"]["name"] for c in calls if c["module"] in ("zypper", "apt", "package")]
        services = [(c["args"]["name"], c["args"]["state"]) for c in calls if c["module"] == "systemd_service"]
        return result, installed, services

    def test_suse_installs_and_starts_docker(self):
        result, installed, services = self._run("Suse")
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertEqual(installed, ["docker", "podman"])
        self.assertEqual(services, [("docker", "started")])

    def test_debian_installs_and_starts_docker(self):
        result, installed, services = self._run("Debian")
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertEqual(installed, ["docker.io", "podman"])
        self.assertEqual(services, [("docker", "started")])

    def test_redhat_gets_the_podman_docker_cli(self):
        result, installed, services = self._run("RedHat")
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertEqual(installed, ["podman-docker", "podman"])
        self.assertEqual(services, [])

    def test_transactional_system_skips_runtime_packages_with_a_warning(self):
        result, installed, services = self._run("Suse", transactional=True)
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertEqual((installed, services), ([], []))
        self.assertIn("read-only root", result.stdout)

    def test_unsupported_family_fails_clearly(self):
        result, installed, _ = self._run("Archlinux")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reports 'Archlinux'", result.stdout)
        self.assertEqual(installed, [])


if __name__ == "__main__":
    unittest.main()
