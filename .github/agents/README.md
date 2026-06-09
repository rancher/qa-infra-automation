# GitHub Copilot CLI — Custom Agents

This folder contains custom agents for the `qa-infra-automation` repository. These agents are invoked via the GitHub Copilot CLI and provide specialized, context-aware assistance for tasks such as infrastructure code review and style enforcement.

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

---

## Authenticating

Launch the CLI and log in:

```bash
copilot login
```

## Launching the CLI

Run `copilot init` from the repository root (or any subdirectory):

```bash
cd /path/to/qa-infra-automation
copilot init
```

Custom agents and repository instructions are loaded automatically from:

- `.github/copilot-instructions.md`
- `.github/agents/*.agent.md`

---

## Using Custom Agents

### Listing available agents

Inside the CLI, run:

```
/agent
```

---

## Available Agents

### `pit.crew.code.style` — Infrastructure Code Style Enforcer

**File:** [`pit.crew.code.style.agent.md`](./pit.crew.code.style.agent.md)

Reviews and fixes Ansible playbooks, OpenTofu modules, and README files to comply with the repository's code style, naming conventions, variable definition patterns, and idempotency standards.

**When to use:** After writing or modifying Ansible roles, playbooks, Tofu modules, or README files — to identify style violations and ensure consistency with project standards before opening a PR.

**Example prompt:**
```
copilot --agent=pit.crew.code.style -p "Review @ansible/roles/rke2_cluster for code style issues"

In an issue or PR comment:
@github-copilot Use the pit.crew.code.style agent to review the changes in this PR
```

---

## Additional Resources

- [GitHub Copilot CLI documentation](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
- [Repository Copilot instructions](../copilot-instructions.md)
