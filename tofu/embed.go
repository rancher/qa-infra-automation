package tofu

import "embed"

// Files contains all OpenTofu/Terraform modules organized by provider
// (aws, gcp, harvester, rancher). Use [github.com/rancher/qa-infra-automation/fsutil.WriteToDisk]
// to extract these files to a directory before running tofu/terraform commands.
//
// The embed directive intentionally omits the "all:" prefix so that
// .terraform/ and .terraform.lock.hcl files are excluded. Note that
// untracked non-dot files (e.g. terraform.tfstate.d/, *.tfvars) that exist
// locally will still be embedded during local builds. When consumed via
// "go get" (the Go module proxy), only git-tracked files are included.
//
//go:embed aws gcp harvester rancher
var Files embed.FS
