
# Building Tofu for GO

Usage:

`import "github.com/rancher/qa-infra-automation/tofu"`

Files is an embed.FS containing all Tofu/Terraform modules.
Paths are relative, e.g. "aws/modules/cluster_nodes/main.tf",
"harvester/modules/vm/main.tf", etc.

`fs.WalkDir(tofu.Files, ".", func(path string, d fs.DirEntry, err error) error { ... })`
