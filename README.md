# Machine Setup

## Tools to install

- git
- jq
- gh CLI
- copilot CLI
- Docker
- .NET SDK (latest release)

### Non-Windows only

- ripgrep

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
- workiq@copilot-plugins
- dotnet-dnceng@dotnet-arcade-skills
- dotnet@awesome-copilot

Install via Copilot CLI:

```
/plugin marketplace add jkoritzinsky/machine-setup
/plugin install notification-tools@machine-setup
/plugin install workiq@copilot-plugins
/plugin install dotnet-dnceng@dotnet-arcade-skills
/plugin install dotnet@awesome-copilot
```
