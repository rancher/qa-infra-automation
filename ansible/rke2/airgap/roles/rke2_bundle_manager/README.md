# RKE2 Bundle Manager Role

This role manages the downloading and bundling of RKE2 artifacts for airgap deployments. It provides a reusable, centralized way to create RKE2 distribution bundles.

## Purpose

The `rke2_bundle_manager` role eliminates code duplication by providing a single, well-tested implementation for:
- Downloading RKE2 artifacts from GitHub releases
- Verifying checksums of downloaded files
- Creating tarball bundles for distribution to airgap nodes

## Features

- **Automatic checksum verification**: Ensures downloaded files are not corrupted
- **Retry logic**: Handles transient network failures with configurable retries
- **Checksum regeneration**: Optionally regenerates checksums on verification failure
- **Configurable cleanup**: Automatic cleanup of temporary files after bundle creation
- **Idempotent**: Can be run multiple times safely

## Requirements

- Ansible 2.9+
- Internet connectivity on the host where the role runs (typically bastion)
- `community.general` collection for archive module

## Role Variables

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `rke2_version` | RKE2 version to download | `v1.33.4+rke2r1` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `rke2_arch` | Target architecture | `amd64` |
| `rke2_temp_dir` | Temporary directory for downloads | `/tmp/rke2-artifacts` |
| `rke2_staging_dir` | Staging directory for bundle creation | `/tmp/rke2-bundle-staging` |
| `rke2_bundle_dir` | Final bundle destination directory | `/opt/rke2-files` |
| `rke2_bundle_filename` | Bundle filename | `rke2-bundle.tar.gz` |
| `rke2_download_timeout` | Download timeout in seconds | `60` |
| `rke2_download_retries` | Number of download retries | `3` |
| `rke2_download_delay` | Delay between retries in seconds | `5` |
| `rke2_verify_checksums` | Whether to verify checksums | `true` |
| `rke2_regenerate_checksums_on_failure` | Regenerate checksums on verification failure | `true` |
| `rke2_cleanup_temp_files` | Cleanup temporary files after bundle creation | `true` |

## Dependencies

None

## Example Playbook

```yaml
---
- name: Create RKE2 bundle on bastion host
  hosts: bastion
  become: true

  vars:
    rke2_version: "v1.31.11+rke2r1"
    rke2_arch: amd64

  roles:
    - role: rke2_bundle_manager
```

## Tasks Included

### download_artifacts.yml
Downloads RKE2 artifacts from GitHub releases:
- RKE2 install script
- RKE2 binary tarball
- RKE2 container images tarball
- SHA256 checksum file

### verify_checksums.yml
Verifies downloaded artifacts against official checksums:
- Extracts expected checksums from checksum file
- Calculates actual checksums of downloaded files
- Compares and reports verification status
- Optionally regenerates checksums on failure

### create_bundle.yml
Creates distribution bundle:
- Sets up staging directory structure
- Copies artifacts to staging area
- Creates compressed tarball bundle
- Verifies bundle creation
- Cleans up temporary files

## Usage in Existing Playbooks

Replace existing bundle creation tasks with this role:

**Before:**
```yaml
- name: Download RKE2 files
  block:
    - name: Download install script
      ansible.builtin.get_url: ...
    - name: Download tarball
      ansible.builtin.get_url: ...
    # ... many more tasks
```

**After:**
```yaml
- name: Create RKE2 bundle
  ansible.builtin.include_role:
    name: rke2_bundle_manager
```

## Bundle Contents

The created bundle contains:
```
rke2-bundle.tar.gz
└── tmp/
    ├── rke2-install.sh
    └── rke2-artifacts/
        ├── rke2.linux-amd64.tar.gz
        ├── rke2-images.tar.gz
        └── sha256sum-amd64.txt
```

## Error Handling

The role includes comprehensive error handling:
- Download failures trigger automatic retries
- Checksum mismatches can regenerate checksums or fail
- Missing files cause immediate failure with clear messages
- Bundle creation failures are reported with detailed information

## Author

QA Infrastructure Automation Team
