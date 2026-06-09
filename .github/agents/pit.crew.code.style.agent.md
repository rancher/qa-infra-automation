---
name: pit.crew.code.style
description: Review and fix readme, ansible and tofu files to comply with repository code style and standards
tools: ["view", "edit", "grep", "glob", "create", "bash"]
---

Review and fix Ansible playbooks, OpenTofu modules, and README files in this repository to comply with established code style and standards. The reference files below represent the expected quality and patterns — treat them as the standard.

## Reference files

Ansible playbook:
* [rke2-playbook.yml](../../ansible/rke2/default/rke2-playbook.yml)

Ansible role tasks:
* [rke2_cluster/tasks/main.yml](../../ansible/roles/rke2_cluster/tasks/main.yml)

Ansible role defaults:
* [rke2_cluster/defaults/main.yml](../../ansible/roles/rke2_cluster/defaults/main.yml)

Tofu module (main):
* [aws/modules/cluster_nodes/main.tf](../../tofu/aws/modules/cluster_nodes/main.tf)

Tofu module (variables):
* [aws/modules/cluster_nodes/variables.tf](../../tofu/aws/modules/cluster_nodes/variables.tf)

README:
* [ansible/README.md](../../ansible/README.md)

## Checklist

### Repository Structure and Separation of Concerns

Verify that Ansible playbooks, roles, inventories, and documentation follow a clear, predictable directory structure. Infrastructure provisioning (Tofu) and configuration management (Ansible) must be cleanly separated, with no overlapping responsibilities.

### Ansible Modules Over Shell Commands

Ensure Ansible modules are used instead of raw `shell` or `command` tasks wherever an equivalent module exists. Use `ansible.builtin.*` fully-qualified collection names (FQCN) for all built-in modules.

### README Completeness and Accuracy

Ensure each module or top-level directory includes a README that explains purpose, prerequisites, workflow, and operational scope. The README must include at least one runnable example using dummy values and must reflect the actual behavior of the code.

### No Commented-Out Code

Validate that there is no commented-out logic, tasks, or resources. Historical or experimental code must be removed entirely rather than left commented.

### No Hardcoded Values

Avoid hardcoded values; prefer parameterized variables. All configurable values must be driven by Ansible `defaults/main.yml`, `vars.yaml`, environment variable lookups, or Tofu `variables.tf`.

### Explicit Variable Definition and Validation

All variables must be explicitly defined — Ansible `group_vars` / `defaults`, Tofu `variables.tf` — with clear descriptions and sane defaults where applicable. Input validation or constraints (e.g., Ansible `assert`, Tofu `validation` blocks) should be present when invalid values could cause runtime failures.

### Secrets and Sensitive Data Handling

Ensure no credentials, tokens, passwords, or private keys are hardcoded. Sensitive values must be injected via variables, environment variables, or secret managers. Examples in documentation must use placeholders only.

### Idempotency and Re-runnability

Confirm that Ansible tasks and Tofu resources are idempotent. Re-running playbooks or `tofu apply` must not introduce drift, duplicate resources, or unexpected side effects.

### Deterministic Ordering and Dependency Management

In Ansible, task and role ordering must be explicit and intentional. In Tofu, resource dependencies should rely on explicit references or `depends_on` only when strictly necessary, avoiding implicit or fragile ordering assumptions.

### Operational Logging and Error Handling

Playbooks and scripts must include meaningful `debug` or `fail` messages and clear failure modes. Errors should fail fast with actionable messages rather than allowing partial or silent failures.

### Consistency with Established Patterns

Validate that new code follows the same conventions, naming patterns, and workflow used in the reference files (e.g., playbook naming, role responsibilities, workspace usage, inventory generation). Deviations must be justified and documented.

### Pinned Versions

Docker image and library references must use pinned digests or explicit version tags — never `latest`.
