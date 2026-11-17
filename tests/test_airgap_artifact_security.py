"""Local regressions for artifact verification and registry configuration."""

import base64
import functools
import fnmatch
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import unittest

import jinja2
import yaml

ROOT = Path(__file__).resolve().parents[1]
ROLES = ROOT / "ansible/roles"


def tasks(role):
    return yaml.safe_load((ROLES / role / "tasks/main.yml").read_text())


def template(text, **variables):
    environment = jinja2.Environment(undefined=jinja2.StrictUndefined)
    environment.filters["to_json"] = json.dumps
    return environment.from_string(text).render(**variables)


class RegistryConfigTests(unittest.TestCase):
    def test_credentials_roundtrip_and_private_source_mirrors(self):
        source = (ROLES / "airgap_product_install/templates/registries.yaml.j2").read_text()
        for mode in ("private", "system_default"):
            with self.subTest(mode=mode):
                config = yaml.safe_load(template(
                    source, airgap_registry_mode=mode, airgap_registry_host="bastion.example.invalid",
                    airgap_registry_mirrors=["docker.io", "registry.k8s.io", "prime.example.invalid:5000"],
                    registry_username='u"ser', registry_password='p"a\\ss#1', airgap_ca_dest="/tmp/ca.crt",
                ))
                self.assertEqual(config["configs"]["bastion.example.invalid"]["auth"],
                                 {"username": 'u"ser', "password": 'p"a\\ss#1'})
                if mode == "private":
                    self.assertIn("prime.example.invalid:5000", config["mirrors"])
                else:
                    self.assertNotIn("mirrors", config, "system-default must select the registry itself")

    def test_both_registry_modes_require_authentication(self):
        start = next(t for t in tasks("airgap_registry") if t["name"] == "Start the registry container")
        for mode in ("private", "system_default"):
            with self.subTest(mode=mode):
                argv = yaml.safe_load(template(start["ansible.builtin.command"]["argv"],
                    airgap_registry_mode=mode, airgap_registry_container="registry", airgap_registry_port=443,
                    airgap_registry_certs_dir="/tmp/certs", airgap_registry_auth_dir="/tmp/auth",
                    airgap_registry_image="registry:test"))
                self.assertIn("REGISTRY_AUTH=htpasswd", argv)
                self.assertIn("/tmp/auth:/auth:ro,Z", argv)

    def test_runtime_archive_is_not_an_image(self):
        find = next(t for t in tasks("airgap_product_install") if "ansible.builtin.find" in t)
        for extension in ("tar.gz", "tar.zst"):
            pattern = template(find["ansible.builtin.find"]["patterns"], tarball_type=extension)
            self.assertFalse(fnmatch.fnmatch("rke2.linux-amd64.tar.gz", pattern))
            for image in ("rke2-images-core.linux-amd64", "k3s-airgap-images-arm64"):
                self.assertTrue(fnmatch.fnmatch(f"{image}.{extension}", pattern))


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook not available")
class ArtifactVerificationTests(unittest.TestCase):
    def test_source_hosts_match_published_names(self):
        source_task = next(t for t in tasks("airgap_image_publish") if
                           "airgap_source_registries" in t.get("ansible.builtin.set_fact", {}))
        publish = yaml.safe_load((ROLES / "airgap_image_publish/tasks/publish_one.yml").read_text())[0]
        cases = {
            "rancher/runtime:v1": "rancher/runtime:v1",
            "docker.io/rancher/runtime:v1": "rancher/runtime:v1",
            "registry.rancher.com/rancher/runtime:v1": "rancher/runtime:v1",
            "prime.example.invalid:5000/rancher/runtime:v1": "rancher/runtime:v1",
            "localhost/rancher/runtime:v1": "rancher/runtime:v1",
        }
        checks = [source_task, {"ansible.builtin.assert": {"that": [
            "airgap_source_registries | sort == expected_sources | sort",
        ]}}]
        for source, target in cases.items():
            checks += [dict(publish, vars={"airgap_image": source}), {"ansible.builtin.assert": {
                "that": [f"airgap_target_image == 'bastion.example.invalid/{target}'"],
            }}]
        with tempfile.TemporaryDirectory() as tmp:
            playbook = Path(tmp) / "mirrors.yml"
            playbook.write_text(yaml.safe_dump([{
                "hosts": "localhost", "connection": "local", "gather_facts": False,
                "vars": {"airgap_images": list(cases), "airgap_registry_host_fact": "bastion.example.invalid",
                         "expected_sources": ["docker.io", "registry.k8s.io", "k8s.gcr.io",
                                              "registry.rancher.com", "prime.example.invalid:5000", "localhost"]},
                "tasks": checks,
            }]))
            env = dict(os.environ, ANSIBLE_LOCAL_TEMP=tmp + "/local", ANSIBLE_REMOTE_TEMP=tmp + "/remote")
            result = subprocess.run(["ansible-playbook", "-i", "localhost,", str(playbook)],
                                    env=env, capture_output=True, text=True, timeout=30, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_every_image_list_line_becomes_one_image(self):
        build = next(t for t in tasks("airgap_image_publish") if t["name"] == "Build the unique image set")
        lists = ["docker.io/rancher/a:1\ndocker.io/rancher/b:2\n", "docker.io/rancher/b:2\n\n  rancher/c:3  \n"]
        play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
                 "vars": {"airgap_image_list_contents": {"results": [
                     {"content": base64.b64encode(text.encode()).decode()} for text in lists]}},
                 "tasks": [build, {"ansible.builtin.assert": {"that": [
                     "airgap_images == ['docker.io/rancher/a:1', 'docker.io/rancher/b:2', 'rancher/c:3']"]}}]}]
        with tempfile.TemporaryDirectory() as tmp:
            playbook = Path(tmp) / "images.yml"
            playbook.write_text(yaml.safe_dump(play))
            env = dict(os.environ, ANSIBLE_LOCAL_TEMP=tmp + "/local", ANSIBLE_REMOTE_TEMP=tmp + "/remote")
            result = subprocess.run(["ansible-playbook", "-i", "localhost,", str(playbook)],
                                    env=env, capture_output=True, text=True, timeout=30, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_each_download_requires_its_exact_checksum(self):
        all_tasks = tasks("airgap_artifacts")
        start = next(i for i, t in enumerate(all_tasks) if t["name"].startswith("Download release"))
        end = next(i for i, t in enumerate(all_tasks) if t["name"] == "Resolve the commit behind the release tag")
        runtime = "rke2.linux-amd64.tar.gz"
        image = "rke2-images.linux-amd64.tar.gz"
        digest = hashlib.sha256(b"fixture artifact").hexdigest()
        runtime_entry = f"{digest}  {runtime}\n"
        cases = {
            "valid": (runtime_entry + f"{digest}  {image}\n", True),
            "binary_marker": (runtime_entry + f"{digest} *{image}\n", True),
            "relative_path": (runtime_entry + f"{digest}  ./{image}\n", True),
            "duplicate_entry": (runtime_entry + f"{digest}  {image}\n" * 2, False),
            "missing_image": (runtime_entry, False),
            "wrong_filename": (runtime_entry + f"{digest}  {image.replace('.', 'X')}\n", False),
            "corrupt_image": (runtime_entry + f"{'0' * 64}  {image}\n", False),
        }

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            source.mkdir()
            for name in (runtime, image):
                (source / name).write_bytes(b"fixture artifact")
            handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(source))
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                for case, (manifest, succeeds) in cases.items():
                    with self.subTest(case=case):
                        (source / "sha256sum-amd64.txt").write_text(manifest)
                        dest = root / case
                        dest.mkdir()
                        play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
                                 "vars": {"airgap_release_files": ["sha256sum-amd64.txt", runtime, image],
                                          "airgap_release_url": f"http://127.0.0.1:{server.server_port}",
                                          "airgap_artifacts_dir": str(dest), "arch": "amd64",
                                          "airgap_download_timeout": 5, "airgap_download_retries": 0,
                                          "airgap_download_delay": 0, "dv_temp_dir": str(dest)},
                                 "tasks": all_tasks[start:end]}]
                        playbook = root / "verify.yml"
                        playbook.write_text(yaml.safe_dump(play))
                        env = dict(os.environ, ANSIBLE_ROLES_PATH=str(ROLES),
                                   ANSIBLE_LOCAL_TEMP=str(root / "local"), ANSIBLE_REMOTE_TEMP=str(root / "remote"))
                        result = subprocess.run(["ansible-playbook", "-i", "localhost,", str(playbook)],
                                                env=env, capture_output=True, text=True, timeout=60, check=False)
                        self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)
                        if succeeds:
                            self.assertEqual((dest / image).read_bytes(), b"fixture artifact")
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)

    def test_prime_release_urls_encode_the_version_plus(self):
        version, runtime = "v1.32.13-rc1+rke2r3", "rke2.linux-amd64.tar.gz"
        defaults = yaml.safe_load((ROLES / "airgap_artifacts/defaults/main.yml").read_text())
        url_vars = {k: defaults[k] for k in ("airgap_origin", "airgap_k3s_release_base",
                                             "airgap_rke2_release_base", "airgap_release_version", "airgap_release_url")}
        all_tasks = tasks("airgap_artifacts")
        start = next(i for i, t in enumerate(all_tasks) if t["name"].startswith("Download release"))
        end = next(i for i, t in enumerate(all_tasks) if t["name"] == "Resolve the commit behind the release tag")
        digest = hashlib.sha256(b"fixture artifact").hexdigest()
        seen = []

        class PrimeLikeHandler(http.server.SimpleHTTPRequestHandler):
            def do_GET(self):
                seen.append(self.path)
                if "+" in self.path:
                    self.send_error(404)
                else:
                    super().do_GET()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            release = root / "source/rke2" / version
            release.mkdir(parents=True)
            (release / runtime).write_bytes(b"fixture artifact")
            (release / "sha256sum-amd64.txt").write_text(f"{digest}  {runtime}\n")
            dest = root / "dest"
            dest.mkdir()
            handler = functools.partial(PrimeLikeHandler, directory=str(root / "source"))
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
                         "vars": dict(url_vars, product="rke2", kubernetes_version=version, arch="amd64",
                                      image_registry_url=f"http://127.0.0.1:{server.server_port}",
                                      airgap_release_files=["sha256sum-amd64.txt", runtime],
                                      airgap_artifacts_dir=str(dest), airgap_download_timeout=5,
                                      airgap_download_retries=0, airgap_download_delay=0, dv_temp_dir=str(dest)),
                         "tasks": all_tasks[start:end]}]
                playbook = root / "prime.yml"
                playbook.write_text(yaml.safe_dump(play))
                env = dict(os.environ, ANSIBLE_ROLES_PATH=str(ROLES),
                           ANSIBLE_LOCAL_TEMP=str(root / "local"), ANSIBLE_REMOTE_TEMP=str(root / "remote"))
                result = subprocess.run(["ansible-playbook", "-i", "localhost,", str(playbook)],
                                        env=env, capture_output=True, text=True, timeout=60, check=False)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(seen and all("%2B" in path and "+" not in path for path in seen), seen)


@unittest.skipUnless(shutil.which("make"), "make not available")
class StateKeyTests(unittest.TestCase):
    def default_state_key(self, *extra):
        out = subprocess.run(["make", "-n", "backend-s3", "BUCKET=b", "REGION=r", "ENV=airgap", *extra],
                             cwd=ROOT, capture_output=True, text=True, timeout=30, check=False).stdout
        return re.search(r'key="([^"]*terraform\.tfstate)"', out).group(1)

    def test_distros_airgap_state_is_apart_from_rancher_airgap(self):
        self.assertEqual(self.default_state_key(), "aws/airgap/terraform.tfstate")
        self.assertEqual(self.default_state_key("AIRGAP_WORKFLOW=distros"), "aws/airgap-distros/terraform.tfstate")


if __name__ == "__main__":
    unittest.main()
