#!/usr/bin/env bash
# Machine setup script for macOS.
set -euo pipefail

step()  { printf '\n\033[36m>>> %s\033[0m\n' "$1"; }
done_() { printf '    \033[32m%s\033[0m\n' "$1"; }
skip()  { printf '    \033[33mSKIP: %s\033[0m\n' "$1"; }

# ── Homebrew ─────────────────────────────────────────────────────────────────

step "Checking for Homebrew"

if ! command -v brew &>/dev/null; then
    echo "    Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # shellcheck disable=SC2016
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
    eval "$(/opt/homebrew/bin/brew shellenv)"
    done_ "Homebrew installed"
else
    skip "Homebrew is already installed"
fi

# ── Tools ────────────────────────────────────────────────────────────────────

step "Installing tools via Homebrew"

formulae=(git gh ripgrep)

for pkg in "${formulae[@]}"; do
    if brew list "$pkg" &>/dev/null; then
        skip "$pkg is already installed"
    else
        brew install "$pkg"
        done_ "$pkg installed"
    fi
done

step "Installing Docker Desktop"

if brew list --cask docker &>/dev/null; then
    skip "Docker Desktop is already installed"
else
    brew install --cask docker
    done_ "Docker Desktop installed"
fi

# ── gh extensions ────────────────────────────────────────────────────────────

step "Installing gh extensions"

gh_extensions=(
    "github/gh-copilot"    # Copilot CLI
    "github/gh-aw"         # Agentic Workflows
    "github/gh-stack"
    "nektos/gh-act"
)

for ext in "${gh_extensions[@]}"; do
    name="${ext##*/}"
    if gh extension list 2>/dev/null | grep -q "$name"; then
        skip "gh extension $ext is already installed"
    else
        echo "    Installing gh extension $ext..."
        gh extension install "$ext"
        done_ "$ext installed"
    fi
done

# ── MCP servers ──────────────────────────────────────────────────────────────

step "Configuring MCP servers"

mcp_dir="$HOME/.config/github-copilot"
mcp_file="$mcp_dir/mcp.json"

# No windbg on macOS
mcp_config='{
  "servers": {
    "github-agentic-workflows": {
      "command": "gh",
      "args": ["aw", "mcp-server"],
      "type": "local"
    }
  }
}'

mkdir -p "$mcp_dir"

if [[ -f "$mcp_file" ]]; then
    skip "MCP config already exists at $mcp_file — review manually"
    echo "    Suggested config:"
    echo "$mcp_config"
else
    echo "$mcp_config" > "$mcp_file"
    done_ "MCP config written to $mcp_file"
fi

# ── Copilot plugins ─────────────────────────────────────────────────────────

step "Copilot plugins (may require org/admin access)"

cat <<'EOF'
    The following Copilot Extensions should be enabled for your account:

      - https://github.com/workiq/copilot-plugins
      - https://github.com/dotnet-dnceng/dotnet-arcade-skills
      - https://github.com/dotnet/awesome-copilot

    Install them from the GitHub Marketplace or your organization's
    Copilot settings at https://github.com/settings/copilot
EOF

# ── Done ─────────────────────────────────────────────────────────────────────

step "Setup complete!"
cat <<EOF
    Remaining manual steps:
      1. Open Docker Desktop and complete first-run setup
      2. Run 'gh auth login' if not already authenticated
      3. Enable the Copilot plugins listed above
EOF
