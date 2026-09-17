# GitHub Copilot CLI — Agent Skills

This folder contains agent skills for the `qa-infra-automation` repository. Skills are folders of instructions Copilot can load automatically when relevant to a task, or invoke explicitly on request.

---

## Installing GitHub Copilot CLI

### Install

**macOS / Linux (Homebrew):**
```bash
brew install copilot-cli
```

**Windows (WinGet):**
```powershell
winget install GitHub.Copilot
```

**npm (all platforms):**
```bash
npm install -g @github/copilot
```

**Install script (macOS / Linux):**
```bash
curl -fsSL https://gh.io/copilot-install | bash
```

### Authenticating

Launch the CLI and log in:

```bash
copilot login
```

### Launching the CLI

Run `copilot init` from the repository root (or any subdirectory):

```bash
cd /path/to/qa-infra-automation
copilot init
```

Repository instructions and skills are loaded automatically from:

- `.github/copilot-instructions.md`
- `.github/skills/*/SKILL.md`

---

## Using Skills

Skills are auto-discovered from `.github/skills/*/SKILL.md` and loaded into context automatically when Copilot judges them relevant to your prompt. You can also invoke one explicitly:

```
Use the /code-review skill to review my staged changes
```

### Listing available skills

Inside the CLI, run:

```
/skills list
```

---

## Available Skills

### `code-review` — Repository Code Reviewer

**File:** [`code-review/SKILL.md`](./code-review/SKILL.md)

Reviews staged/unstaged changes or a PR diff across Go, Python, Ansible, and OpenTofu for logic bugs, broken contracts (Tofu outputs, inventory schema, Go APIs), missing test coverage, and security issues.

**When to use:** Before opening a PR, or when asked to review a diff, to catch correctness and security issues and confirm the repository's contract-preservation and testing requirements are met.

**Example prompt:**
```
Use the /code-review skill to review my staged changes to tofu/aws/modules/cluster_nodes

In an issue or PR comment:
@github-copilot Use the code-review skill to review the changes in this PR
```

---

## Additional Resources

- [GitHub Copilot CLI documentation](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
- [Adding agent skills for GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills)
- [Repository Copilot instructions](../copilot-instructions.md)
