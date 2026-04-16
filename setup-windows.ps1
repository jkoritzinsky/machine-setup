<#
.SYNOPSIS
    Machine setup script for Windows.
.DESCRIPTION
    Installs tools, gh extensions, configures MCP servers,
    and provides instructions for Copilot plugins.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Host "`n>>> $Message" -ForegroundColor Cyan }
function Write-Done { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Skip { param([string]$Message) Write-Host "    SKIP: $Message" -ForegroundColor Yellow }

# ── Tools ────────────────────────────────────────────────────────────────────

Write-Step "Installing tools via winget"

$tools = @(
    @{ Id = 'Git.Git';              Name = 'Git' },
    @{ Id = 'jqlang.jq';            Name = 'jq' },
    @{ Id = 'GitHub.cli';           Name = 'GitHub CLI (gh)' },
    @{ Id = 'Docker.DockerDesktop'; Name = 'Docker Desktop' }
)

foreach ($tool in $tools) {
    $installed = winget list --id $tool.Id --accept-source-agreements 2>&1 |
                 Select-String $tool.Id
    if ($installed) {
        Write-Skip "$($tool.Name) is already installed"
    } else {
        Write-Host "    Installing $($tool.Name)..."
        winget install --id $tool.Id -e --source winget --accept-package-agreements --accept-source-agreements
        Write-Done "$($tool.Name) installed"
    }
}

# Refresh PATH so gh is available in this session
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path', 'User')

# Note: ripgrep is NOT installed on Windows (README: "Non-Windows only")

# ── gh extensions ────────────────────────────────────────────────────────────

Write-Step "Installing gh extensions"

$ghExtensions = @(
    'github/gh-copilot',   # Copilot CLI
    'github/gh-aw',        # Agentic Workflows
    'github/gh-stack',
    'nektos/gh-act'
)

foreach ($ext in $ghExtensions) {
    $name = ($ext -split '/')[-1]
    $existing = gh extension list 2>&1 | Select-String $name
    if ($existing) {
        Write-Skip "gh extension $ext is already installed"
    } else {
        Write-Host "    Installing gh extension $ext..."
        gh extension install $ext
        Write-Done "$ext installed"
    }
}

# ── MCP servers ──────────────────────────────────────────────────────────────

Write-Step "Configuring MCP servers"

$mcpDir  = Join-Path $env:USERPROFILE '.config\github-copilot'
$mcpFile = Join-Path $mcpDir 'mcp.json'

$username = $env:USERNAME

$mcpConfig = @{
    servers = [ordered]@{
        'github-agentic-workflows' = [ordered]@{
            command = 'gh'
            args    = @('aw', 'mcp-server')
            type    = 'local'
        }
        'windbg' = [ordered]@{
            command = "C:/Users/$username/AppData/Local/Microsoft/WindowsApps/DbgX.Mcp.Proxy.exe"
            type    = 'stdio'
        }
    }
} | ConvertTo-Json -Depth 5

if (-not (Test-Path $mcpDir)) { New-Item -ItemType Directory -Path $mcpDir -Force | Out-Null }

if (Test-Path $mcpFile) {
    Write-Skip "MCP config already exists at $mcpFile — review manually"
    Write-Host "    Suggested config:"
    Write-Host $mcpConfig
} else {
    Set-Content -Path $mcpFile -Value $mcpConfig -Encoding UTF8
    Write-Done "MCP config written to $mcpFile"
}

# ── Copilot plugins ─────────────────────────────────────────────────────────

Write-Step "Copilot plugins (may require org/admin access)"

$plugins = @(
    'workiq/copilot-plugins',
    'dotnet-dnceng/dotnet-arcade-skills',
    'dotnet/awesome-copilot'
)

Write-Host @"
    The following Copilot Extensions should be enabled for your account:

"@

foreach ($plugin in $plugins) {
    Write-Host "      - https://github.com/$plugin"
}

Write-Host @"

    Install them from the GitHub Marketplace or your organization's
    Copilot settings at https://github.com/settings/copilot
"@

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Step "Setup complete!"
Write-Host @"
    Remaining manual steps:
      1. Sign in to Docker Desktop and start the service
      2. Run 'gh auth login' if not already authenticated
      3. Enable the Copilot plugins listed above
      4. Verify windbg MCP proxy is installed via Microsoft Store (WinDbg Preview)
"@
