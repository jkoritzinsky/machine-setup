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
    @{ Id = 'Microsoft.DotNet.SDK.9'; Name = '.NET SDK' }
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

# ── WSL ──────────────────────────────────────────────────────────────────────

Write-Step "Installing WSL"

wsl --status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "    Installing WSL..."
    wsl --install --no-launch
    Write-Done "WSL installed"
} else {
    Write-Skip "WSL is already installed"
}

Write-Step "Ensuring wslc (WSL Containers) is available"

$wslcAvailable = $null -ne (Get-Command wslc -ErrorAction SilentlyContinue)
if (-not $wslcAvailable) {
    $wslcOutput = wsl --help 2>&1 | Out-String
    $wslcAvailable = $wslcOutput -match '\bwslc\b'
}

if ($wslcAvailable) {
    Write-Skip "wslc is already available"
} else {
    Write-Host "    wslc not found; updating WSL to the pre-release channel..."
    wsl --update --pre-release
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update WSL to the pre-release channel (exit code $LASTEXITCODE)"
    }
    wsl --shutdown
    Write-Done "WSL updated to pre-release; wslc should now be available"
}

# ── Dotnet tools ────────────────────────────────────────────────────────────

Write-Step "Installing global dotnet tools"

$dotnetTools = @(
    'binloginsights.mcp'
)

foreach ($tool in $dotnetTools) {
    $existing = dotnet tool list -g 2>&1 | Select-String "^$tool\s"
    if ($existing) {
        Write-Skip "dotnet tool $tool is already installed"
    } else {
        Write-Host "    Installing dotnet tool $tool..."
        dotnet tool install -g $tool
        Write-Done "dotnet tool $tool installed"
    }
}

# ── gh extensions ────────────────────────────────────────────────────────────

Write-Step "Installing gh extensions"

$ghExtensions = @(
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

# ── Copilot CLI ──────────────────────────────────────────────────────────────

Write-Step "Installing Copilot CLI"

$copilotExtensionInstalled = gh extension list 2>$null | Select-String '^gh-copilot\b'
if ($copilotExtensionInstalled) {
    Write-Skip "Copilot CLI is already installed"
} else {
    gh extension install github/gh-copilot
    Write-Done "Copilot CLI installed"
}

# ── Copilot plugins ─────────────────────────────────────────────────────────

Write-Step "Installing Copilot plugins"

$copilotExtensionInstalled = gh extension list 2>$null | Select-String '^gh-copilot\b'
if (-not $copilotExtensionInstalled) {
    Write-Skip "Copilot CLI not found; skipping Copilot plugin installation"
} else {
    function Invoke-CopilotPluginCommand {
        param(
            [Parameter(Mandatory=$true)][string]$Label,
            [Parameter(Mandatory=$true)][string[]]$Args
        )

        $output = & gh copilot @Args 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Done $Label
        } elseif (($output | Out-String) -match 'already') {
            Write-Skip "$Label is already configured"
        } else {
            throw "gh copilot $($Args -join ' ') failed: $output"
        }
    }

    Invoke-CopilotPluginCommand -Label "Added marketplace jkoritzinsky/machine-setup" -Args @('plugin', 'marketplace', 'add', 'jkoritzinsky/machine-setup')
    Invoke-CopilotPluginCommand -Label "Added marketplace dotnet/arcade-skills" -Args @('plugin', 'marketplace', 'add', 'dotnet/arcade-skills')
    Invoke-CopilotPluginCommand -Label "Installed notification-tools@machine-setup" -Args @('plugin', 'install', 'notification-tools@machine-setup')
    Invoke-CopilotPluginCommand -Label "Installed workiq@copilot-plugins" -Args @('plugin', 'install', 'workiq@copilot-plugins')
    Invoke-CopilotPluginCommand -Label "Installed dotnet-dnceng@dotnet-arcade-skills" -Args @('plugin', 'install', 'dotnet-dnceng@dotnet-arcade-skills')
    Invoke-CopilotPluginCommand -Label "Installed dotnet@awesome-copilot" -Args @('plugin', 'install', 'dotnet@awesome-copilot')
}

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Step "Setup complete!"
Write-Host @"
    Remaining manual steps:
      1. Restart your machine if WSL was just installed for the first time
      2. Run 'gh auth login' if not already authenticated
      3. Add '%USERPROFILE%\\.dotnet\\tools' to PATH if dotnet tools are not found
      4. Verify windbg MCP proxy is installed via Microsoft Store (WinDbg Preview)
"@
