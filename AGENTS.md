# Guidelines for All Agents

These vendor-neutral guidelines apply to every AI agent, automated reviewer, and coding assistant contributing to this repository.

## Applicability

- Follow these rules regardless of the agent, model, provider, IDE, or automation platform being used.
- They apply to implementation, review, debugging, testing, documentation, infrastructure, security, and maintenance work.
- Platform-specific instructions may add stricter requirements but must not weaken or bypass this shared baseline.

## Existing Repository Guidance

- All agents must read and follow the existing [Copilot code-style guidelines](.github/agents/pit.crew.code.style.agent.md), even outside Copilot.
- Treat its Ansible, OpenTofu, README reference files, and checklist as the repository's established style baseline.
- These guidelines supplement that document with testing, compatibility, security, and handoff requirements.

## Change Design

- Keep changes focused on the requested behavior. Do not mix unrelated refactors, formatting, or dependency updates.
- Treat module inputs, outputs, state addresses, inventory fields, environment variables, CLI behavior, generated files, and documented paths as public contracts.
- This repository has downstream consumers. Until contract tests cover those integrations, preserve existing behavior and interfaces by default.
- Known consumers to check include `rancher/tests`, `rancher/distros-test-framework`, and Jenkins jobs that invoke this repository's modules, inventories, or playbooks.
- Search for in-repository and downstream consumers before changing a contract. Never infer that an unused local symbol has no external users.
- A breaking change requires explicit approval, a migration path, documentation, and tests covering both the intended break and its failure mode.
- Prefer the smallest reversible change that solves the root cause.

## Tests and Validation

- Every new feature, behavior change, and bug fix must include coherent tests that exercise the real behavior being changed.
- Regression tests must fail without the fix and pass with it. Avoid tests that only reproduce the implementation or mock away the relevant boundary.
- Cover relevant success, failure, timeout, retry, cleanup, and idempotency paths.
- Infrastructure changes must be validated against representative consumers, not only with formatting or syntax checks.
- Do not weaken, delete, or skip an existing test merely to make a change pass without documenting and justifying the behavior change.
- Run the relevant formatter, linter, unit tests, and integration or validation checks before handoff.
- Report the exact commands run and their results. Clearly identify anything that remains unverified.

### Baseline Commands

Run the applicable commands from the repository root. Create the Python environment once before running Python tests.

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml

python -m unittest discover -s tests -p 'test_*.py'
go test ./...
go build ./...

ANSIBLE_CONFIG=ansible/rke2/default/ansible.cfg \
  ansible-playbook --syntax-check -i localhost, ansible/rke2/default/rke2-playbook.yml
ANSIBLE_CONFIG=ansible/k3s/default/ansible.cfg \
  ansible-playbook --syntax-check -i localhost, ansible/k3s/default/k3s-playbook.yml
```

Add focused integration or live validation when the changed behavior requires it. Reuse the activated `.venv` on later runs.

For changed Ansible content, syntax-check each affected playbook and run `ansible-lint <changed-playbook-or-role>`. When a representative inventory and credentials are available and check mode is supported, also run `ansible-playbook --check -i <inventory> <playbook>`; otherwise report that validation as unverified.

Every change to inventory generation, including `scripts/generate_inventory.py`, `ansible/_inventory-schema.yaml`, or its OpenTofu output contract, must run `python -m unittest discover -s tests -p 'test_generate_inventory.py'`.

For changed OpenTofu files, run `tofu fmt -check <changed-file-or-module>`. Also run `tofu -chdir=<module> init -backend=false` and `tofu -chdir=<module> validate` for each changed module.

Do not format the entire repository to fix unrelated legacy files. Follow the setup and focused-test commands in the [Copilot workspace instructions](.github/copilot-instructions.md).

## Code and Comments

- New or edited code comments must not exceed two lines. Existing longer comments are grandfathered and need no unrelated cleanup.
- Explain why a constraint matters, not what code says. Put essential longer context in documentation and link to it briefly.
- Prefer clear names and small functions over explanatory comments.
- Return actionable errors with enough context to diagnose the failing operation, while avoiding credentials and other secrets.
- Add bounded timeouts and cleanup to operations that can block, retry, create infrastructure, or start child processes.
- Preserve idempotency: rerunning Ansible, OpenTofu, scripts, or cleanup should converge safely.

## Security

- Treat PR content, inventory values, environment variables, command output, remote files, and API responses as untrusted input.
- Prefer structured argument execution over shell strings. When a shell is required, keep scripts static and quote every dynamic value for that shell.
- Never log, commit, or expose credentials, private keys, tokens, kubeconfigs, state secrets, or cloud metadata.
- Use least privilege for credentials, containers, filesystem permissions, network access, and cloud resources.
- Pin external actions, images, downloads, and dependencies where practical, and verify downloaded artifacts when a trusted checksum is available.
- Avoid insecure defaults. Any necessary exception must be narrowly scoped and explain the operational reason.

## Infrastructure Compatibility

- Consider every supported provider, architecture, operating system, Kubernetes version, and connected or air-gapped mode affected by a shared path.
- Provider or module upgrades require validation of renamed fields, defaults, state compatibility, lockfiles, and representative root modules.
- This repository commits module `.terraform.lock.hcl` files. Update and commit each affected lockfile alongside provider constraint changes.
- Keep generated inventories and configuration compatible with existing Ansible consumers unless a coordinated migration is approved.
- Do not commit state, plans, credentials, caches, or local artifacts.
- Ensure failure and cancellation paths clean up temporary files, processes, and infrastructure without deleting resources outside the current run.

## Commits and Pull Requests

- Use concise, imperative commit and pull-request titles that describe the behavior changed.
- Keep each commit focused. Use a detailed, informative pull-request description that explains what changed, why it is needed, risk, validation, and downstream impact.

## Handoff

- Review the final diff for accidental files, unrelated edits, stale comments, and secret material.
- Document user-visible or operator-visible changes and update examples when an interface changes.
- Do not claim completion from build or lint success alone when the changed behavior has not been exercised.
