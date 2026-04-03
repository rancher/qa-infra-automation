# Supply Chain Security

This document describes the supply chain hardening measures in this repository.

## Threat Model

**Primary threat:** Compromised upstream artifacts — malicious binaries or scripts injected into CDN mirrors or GitHub releases.

**Out of scope:** MITM attacks (mitigated by TLS), insider threats, CI/CD pipeline compromise.

## Verification Patterns

### Verified Binary Download

Used for all binary and tarball downloads. Downloads the artifact and its companion SHA256 checksum from the same release, verifies they match, then uses the artifact.

**Implemented by:** `ansible/roles/download_verify/` shared role

**Used for:** K3s binary, Helm tarball, kubectl binary, Docker tarball, OpenTofu zip, cert-manager manifests

### Version-Pinned Install Scripts

When a specific version is requested, install scripts are fetched from a version-tagged git ref instead of a floating redirect.

**Used for:** RKE2 install script (`raw.githubusercontent.com/rancher/rke2/<version>/install.sh`), helm-diff plugin (`--version` flag)

### Helm Chart Verification

All `kubernetes.core.helm` chart installs attempt `verify: true` first. If the chart has a signed provenance file, verification passes. If unsigned (most public charts), the install falls back to unverified with a warning.

### Terraform Provider Locking

All Terraform/OpenTofu root modules include `.terraform.lock.hcl` files that pin exact provider versions with SHA256 hashes. OpenTofu verifies provider integrity against these hashes on every `tofu init`.

## Verification Command

```bash
make verify
```

This checks:

- Python dependencies are pinned in `requirements.txt`
- Ansible collections are pinned in `requirements.yml`
- `.terraform.lock.hcl` files exist for all root modules
- The `download_verify` role is present

## Adding New Downloads

When adding a new binary or tarball download:

1. Use the `download_verify` role instead of raw `get_url`
2. Find the SHA256 checksum URL from the same release
3. Choose the appropriate `dv_checksum_format`:
   - `github_sha256sum` — grep for filename in GitHub sha256sum-\*.txt
   - `sha256sum_file` — single-line checksum file
   - `sha256sum_inline` — hardcoded checksum value

Example:

```yaml
- name: Download my-tool with verification
  include_role:
    name: download_verify
  vars:
    dv_artifact_url: "https://github.com/org/repo/releases/download/v{{ version }}/tool"
    dv_checksum_url: "https://github.com/org/repo/releases/download/v{{ version }}/sha256sum-amd64.txt"
    dv_dest: "/usr/local/bin/tool"
    dv_checksum_format: "github_sha256sum"
    dv_github_artifact_name: "tool"
    dv_mode: "0755"
```
