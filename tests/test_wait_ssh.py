"""wait-ssh.yml must retry an unreachable host and give up after ssh_wait_attempts.

A fake ssh executable reports UNREACHABLE (exit 255) for the first N calls,
then runs the remote command locally, so the real retry path is exercised.
"""

import os
import shutil
import stat
import subprocess
import tempfile
import unittest

REPOSITORY_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
WAIT_SSH = os.path.join(REPOSITORY_ROOT, "ansible", "rke2", "shared", "wait-ssh.yml")

FAKE_SSH = """#!/bin/sh
n=$(cat "$COUNT_FILE" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$COUNT_FILE"
if [ "$n" -le "$FAILS" ]; then
  echo "ssh: connect to host fake port 22: Connection refused" >&2
  exit 255
fi
for last; do :; done
exec /bin/sh -c "$last"
"""

PLAY = """- hosts: node
  gather_facts: false
  tasks:
    - ansible.builtin.include_tasks: {wait_ssh}
      vars:
        ssh_wait_attempts: 4
        ssh_wait_delay: 0
"""


@unittest.skipIf(shutil.which("ansible-playbook") is None, "ansible-playbook is required")
class TestWaitSsh(unittest.TestCase):
    def _run(self, fails):
        with tempfile.TemporaryDirectory() as tmpdir:
            fake_ssh = os.path.join(tmpdir, "ssh")
            with open(fake_ssh, "w", encoding="utf-8") as handle:
                handle.write(FAKE_SSH)
            os.chmod(fake_ssh, stat.S_IRWXU)
            with open(os.path.join(tmpdir, "inventory"), "w", encoding="utf-8") as handle:
                handle.write(
                    f"node ansible_host=fake.invalid ansible_connection=ssh "
                    f"ansible_ssh_executable={fake_ssh} ansible_ssh_pipelining=false\n"
                )
            with open(os.path.join(tmpdir, "play.yml"), "w", encoding="utf-8") as handle:
                handle.write(PLAY.format(wait_ssh=WAIT_SSH))
            count_file = os.path.join(tmpdir, "count")
            result = subprocess.run(
                ["ansible-playbook", "-i", "inventory", "play.yml"],
                cwd=tmpdir,
                env=dict(os.environ, COUNT_FILE=count_file, FAILS=str(fails),
                         ANSIBLE_SSH_RETRIES="0", ANSIBLE_RETRY_FILES_ENABLED="0"),
                capture_output=True,
                text=True,
                check=False,
                timeout=180,
            )
            with open(count_file, encoding="utf-8") as handle:
                calls = int(handle.read())
        return result, calls

    def test_retries_until_the_host_answers(self):
        result, calls = self._run(fails=2)
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertEqual(calls, 3)

    def test_already_reachable_host_is_probed_once(self):
        result, calls = self._run(fails=0)
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)
        self.assertEqual(calls, 1)

    def test_gives_up_after_ssh_wait_attempts(self):
        result, calls = self._run(fails=100)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SSH to node not ready after 4 attempts", result.stdout)
        self.assertEqual(calls, 4)


if __name__ == "__main__":
    unittest.main()
