"""Exercise the Make and Ansible boundaries fixed by the Airgap review."""

import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
ROLES = ROOT / "ansible/roles"


def role_tasks(role):
    return yaml.safe_load((ROLES / role / "tasks/main.yml").read_text())


class AirgapReviewRegressions(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)

    def run_tasks(self, role, tasks, variables):
        defaults = yaml.safe_load((ROLES / role / "defaults/main.yml").read_text())
        play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
                 "vars": {**defaults, **variables}, "tasks": tasks}]
        playbook = self.directory / "play.yml"
        playbook.write_text(yaml.safe_dump(play))
        env = dict(os.environ, ANSIBLE_ROLES_PATH=str(ROLES),
                   ANSIBLE_LOCAL_TEMP=str(self.directory / "local"),
                   ANSIBLE_REMOTE_TEMP=str(self.directory / "remote"))

        return subprocess.run(["ansible-playbook", "-i", "localhost,", str(playbook)],
                              env=env, capture_output=True, text=True, timeout=60, check=False)

    def test_composite_make_targets_only_install_rancher_when_configured(self):
        for target in ("all", "setup-from-infra"):
            for environment, workflow in (("airgap", ""), ("default", "")):
                with self.subTest(target=target, environment=environment, workflow=workflow):
                    result = subprocess.run(
                        ["make", "-n", target, "OFFLINE=1", "-o", "infra-up", "-o", "check-inventory",
                         "-o", "status", f"ENV={environment}", f"AIRGAP_WORKFLOW={workflow}",
                         "UI_PLUGIN_MIRROR_TARGET=", "CHARTS_MIRROR_TARGET=", "REGISTRY_TARGET="],
                        cwd=ROOT, capture_output=True, text=True, timeout=30, check=False)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    commands = [line.strip() for line in result.stdout.splitlines()
                                if line.lstrip().startswith("ansible-playbook ")]
                    self.assertTrue(commands, result.stdout)
                    self.assertTrue(all("-playbook.yml" in line or "bootstrap-python.yml" in line
                                        for line in commands), commands)
                    rancher = [line for line in commands if "rancher" in line]
                    self.assertEqual(bool(rancher), workflow != "distros", commands)

    def test_distros_make_rejects_cluster_targets_before_provisioning(self):
        for target in ("cluster", "bootstrap-python", "all", "setup-from-infra", "airgap-downstream", "infra-up"):
            with self.subTest(target=target):
                result = subprocess.run(
                    ["make", "-n", "-j6", target, "ENV=airgap", "AIRGAP_WORKFLOW=distros"],
                    cwd=ROOT, capture_output=True, text=True, timeout=30, check=False)
                if target == "infra-up":
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("tofu apply", result.stdout)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("use infra-up and the direct Ansible workflow", result.stderr)
                    self.assertNotIn("tofu apply", result.stdout)

    def test_invalid_artifact_components_fail_before_creating_the_cache(self):
        tasks = role_tasks("airgap_artifacts")
        end = next(i for i, task in enumerate(tasks) if task["name"] == "Create artifact directory") + 1
        cases = [
            ("rke2", "v1.36.0+rke2r1", "multus,canal", True),
            ("rke2", "v1.32.13-rc1+rke2r3", "", True),
            ("k3s", "v1.36.0+k3s1", "", True),
            ("rke2", "v1.36.0+rke2r1/../../../escape", "", False),
            ("rke2", "v1.36.0+rke2r1\n", "", False),
            ("rke2", "v1.36.0+k3s1", "", False),
            ("rke2", "v1.36.0+rke2r1", "canal/../../escape", False),
            ("rke2", "v1.36.0+rke2r1", "typo", False),
            ("rke2", "v1.36.0+rke2r1", "multus,typo", False),
            ("rke2", "v1.36.0+rke2r1", "none", True),
            ("rke2", "v1.36.0+rke2r1", "calico", True),
            ("rke2", "v1.36.0+rke2r1", "cilium", True),
            ("rke2", "v1.36.0+rke2r1", "flannel", True),
        ]
        for index, (product, version, cni, succeeds) in enumerate(cases):
            with self.subTest(product=product, version=version, cni=cni):
                cache = self.directory / str(index)
                result = self.run_tasks("airgap_artifacts", tasks[:end], {
                    "product": product, "kubernetes_version": version, "cni": cni,
                    "airgap_bastion_dir": str(cache), "airgap_method": "tarball"})
                self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)
                self.assertEqual(cache.exists(), succeeds)

        result = self.run_tasks("airgap_artifacts", tasks[:end], {
            "product": "rke2", "kubernetes_version": "v1.36.0+rke2r1",
            "server_flags": "cni: [multus, typo]", "airgap_method": "tarball",
            "airgap_bastion_dir": str(self.directory / "from-flags")})
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.directory / "from-flags").exists())

    def test_rke2_traefik_selection_matches_release_layout(self):
        tasks = role_tasks("airgap_artifacts")
        start = next(i for i, task in enumerate(tasks) if task["name"] == "Build the RKE2 image list selection")
        end = next(i for i, task in enumerate(tasks) if task["name"] == "Download release lists")
        selected = self.directory / "selected.json"
        capture = {"ansible.builtin.copy": {"dest": str(selected), "mode": "0600",
                                             "content": "{{ airgap_release_files | to_json }}"}}
        for version in ("v1.35.7+rke2r1", "v1.36.0-rc1+rke2r1", "v1.36.0+rke2r1"):
            for method in ("tarball", "private_registry"):
                with self.subTest(version=version, method=method):
                    result = self.run_tasks("airgap_artifacts", tasks[start:end] + [capture], {
                        "product": "rke2", "kubernetes_version": version, "cni": "canal",
                        "server_flags": "ingress-controller: traefik", "airgap_method": method})
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    files = json.loads(selected.read_text())
                    self.assertIn("rke2-images-core.linux-amd64.txt", files)
                    self.assertIn("rke2-images-canal.linux-amd64.txt", files)
                    self.assertEqual("rke2-images-traefik.linux-amd64.txt" in files, "1.35" in version)
                    self.assertEqual("rke2-images-traefik.linux-amd64.tar.zst" in files,
                                     "1.35" in version and method == "tarball")

    def test_rke2_lists_require_checksums_while_k3s_lists_remain_supported(self):
        tasks = role_tasks("airgap_artifacts")
        start = next(i for i, task in enumerate(tasks) if task["name"] == "Download release lists")
        end = next(i for i, task in enumerate(tasks) if task["name"] == "Resolve the commit behind the release tag")
        source = self.directory / "source"
        source.mkdir()
        body = b"docker.io/example/fixture:1\n"
        digest = hashlib.sha256(body).hexdigest()
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(source))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        try:
            for product, checksum in (("rke2", digest), ("rke2", "0" * 64), ("rke2", ""), ("k3s", "")):
                with self.subTest(product=product, checksum=checksum):
                    name = "rke2-images-core.linux-amd64.txt" if product == "rke2" else "k3s-images.txt"
                    (source / name).write_bytes(body)
                    (source / "sha256sum-amd64.txt").write_text(f"{checksum}  {name}\n" if checksum else "")
                    with tempfile.TemporaryDirectory(dir=self.directory) as destination:
                        result = self.run_tasks("airgap_artifacts", tasks[start:end], {
                            "product": product, "airgap_release_files": ["sha256sum-amd64.txt", name],
                            "airgap_release_url": f"http://127.0.0.1:{server.server_port}",
                            "airgap_artifacts_dir": destination, "airgap_download_timeout": 5,
                            "airgap_download_retries": 0, "airgap_download_delay": 0})
                        succeeds = product == "k3s" or checksum == digest
                        self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)
                        if succeeds:
                            self.assertEqual((Path(destination) / name).read_bytes(), body)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_kubeconfig_tempfile_is_removed_on_success_and_copy_failures(self):
        for failure in ("", "bastion", "diagnostics"):
            with self.subTest(failure=failure):
                tasks = role_tasks("airgap_cluster_access")
                end = next(i for i, task in enumerate(tasks) if task["name"].startswith("Wait until every node"))
                tasks = tasks[:end]
                tasks[0]["ansible.builtin.tempfile"]["path"] = str(self.directory)
                fixture = self.directory / "fixture.yaml"
                fixture.write_text("server: https://127.0.0.1:6443\ntoken: dummy-fixture\n")

                # Only the remote source/privilege boundary changes; fetch, copies and cleanup run.
                for task in tasks:
                    for nested in task.get("block", [task]):
                        if "ansible.builtin.fetch" in nested:
                            nested["ansible.builtin.fetch"]["src"] = str(fixture)
                            nested["become"] = False

                bastion = self.directory / ("missing/bastion.yaml" if failure == "bastion" else "bastion.yaml")
                diagnostics = self.directory / ("missing/diagnostics.yaml" if failure == "diagnostics" else "diagnostics.yaml")
                result = self.run_tasks("airgap_cluster_access", tasks, {
                    "product": "k3s", "airgap_master_host": "localhost", "airgap_master_ip": "node.example.invalid",
                    "ansible_user": str(os.getuid()), "bastion_kubeconfig_path": str(bastion),
                    "kubeconfig_file": str(diagnostics)})
                self.assertEqual(result.returncode == 0, not failure, result.stdout + result.stderr)
                self.assertEqual(list(self.directory.glob("dtf-airgap-kc-*")), [], result.stdout)
                if not failure:
                    self.assertIn("node.example.invalid", diagnostics.read_text())
                    self.assertEqual(diagnostics.stat().st_mode & 0o777, 0o600)

    def test_registry_hostname_fallback_and_empty_value_guard(self):
        tasks = role_tasks("airgap_registry")
        end = next(i for i, task in enumerate(tasks) if task["name"] == "Generate the registry TLS certificate") + 1
        cases = [(None, "fallback.example.invalid"), ("", "fallback.example.invalid"),
                 ("registry.example.invalid", "registry.example.invalid")]
        for public_dns, expected in cases + [("", "")]:
            with self.subTest(public_dns=public_dns, expected=expected):
                with tempfile.TemporaryDirectory(dir=self.directory) as directory:
                    variables = {"ansible_facts": {"fqdn": "fallback.example.invalid" if expected else ""},
                                 "airgap_registry_certs_dir": directory, "airgap_registry_auth_dir": directory}
                    if public_dns is not None:
                        variables["bastion_public_dns"] = public_dns
                    result = self.run_tasks("airgap_registry", tasks[:end], variables)
                    self.assertEqual(result.returncode == 0, bool(expected), result.stdout + result.stderr)
                    if expected:
                        certificate = subprocess.run(
                            ["openssl", "x509", "-in", str(Path(directory) / "domain.crt"), "-noout", "-ext", "subjectAltName"],
                            capture_output=True, text=True, timeout=10, check=False)
                        self.assertEqual(certificate.returncode, 0, certificate.stderr)
                        self.assertIn("DNS:" + expected, certificate.stdout)
                    else:
                        self.assertIn("Set airgap_registry_host", result.stdout)


if __name__ == "__main__":
    unittest.main()
