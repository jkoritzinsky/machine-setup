# Machine Setup

## Tools to install

- git
- jq
- gh CLI
- copilot CLI
- .NET SDK (latest release)

### Non-Windows only

- Docker
- ripgrep

### Windows only

- WSL (with wslc / WSL Containers available; WSL is updated to the pre-release channel if wslc is not present)

## Dotnet tools (dotnet tool install -g)

- binloginsights.mcp

## gh extensions

- github/gh-aw
- github/gh-stack
- nektos/gh-act

## MCP servers

- github-agentic-workflows: gh aw mcp-server, local

### Windows-only

- windbg: C:/Users/%USER%/AppData/Local/Microsoft/WindowsApps/DbgX.Mcp.Proxy.exe, stdio (Replace %USER% with account username)

## Copilot plugins

- notification-tools@machine-setup (this repo)
- session-stacks@machine-setup (this repo)
- workiq@copilot-plugins
- dotnet-dnceng@dotnet-arcade-skills
- dotnet@awesome-copilot

Install via Copilot CLI:

```
copilot plugin marketplace add jkoritzinsky/machine-setup
copilot plugin marketplace add dotnet/arcade-skills
copilot plugin install notification-tools@machine-setup
copilot plugin install session-stacks@machine-setup
copilot plugin install workiq@copilot-plugins
copilot plugin install dotnet-dnceng@dotnet-arcade-skills
copilot plugin install dotnet@awesome-copilot
```

The [session-stacks plugin](plugins/session-stacks/README.md) includes
`create-session-stack` and `rebase-session-stack`, their supporting protocols,
guarded Git helpers, and disposable fixture tests. Creating layer sessions
requires an explicit session-stack request; setup grants no standing rebase or
publication authority. See the plugin README for prerequisites and local checks.

When working in this repository with experimental extensions enabled, the
`github-notification-triage` canvas provides an interactive view of GitHub
notifications and pull request review status. Its triage and cleanup rules are
shared with the `notification-tools` plugin skills. The dashboard's **Run
notification cleanup** button starts the `notification-cleanup` skill in the
active chat; that skill retains its safety checks and confirmation step.
