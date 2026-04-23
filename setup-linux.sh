#!/usr/bin/env bash
# Machine setup script for Linux (apt/dnf based distros).
set -euo pipefail

step()  { printf '\n\033[36m>>> %s\033[0m\n' "$1"; }
done_() { printf '    \033[32m%s\033[0m\n' "$1"; }
skip()  { printf '    \033[33mSKIP: %s\033[0m\n' "$1"; }

# ── Tools ────────────────────────────────────────────────────────────────────

step "Installing tools via apt"
sudo apt-get update -qq

for pkg in git jq ripgrep; do
    if dpkg -s "$pkg" &>/dev/null; then
        skip "$pkg is already installed"
    else
        sudo apt-get install -y -qq "$pkg"
        done_ "$pkg installed"
    fi
done

# ── GitHub CLI ───────────────────────────────────────────────────────────────

step "Installing GitHub CLI (gh)"

if command -v gh &>/dev/null; then
    skip "gh is already installed"
else
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq && sudo apt-get install -y -qq gh
    done_ "gh installed"
fi

# ── Docker ───────────────────────────────────────────────────────────────────

step "Installing Docker"

if command -v docker &>/dev/null; then
    skip "Docker is already installed"
else
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    done_ "Docker installed (log out and back in for group changes)"
fi

# ── .NET SDK ─────────────────────────────────────────────────────────────────

step "Installing .NET SDK via package manager"

if command -v dotnet &>/dev/null; then
    skip ".NET SDK is already installed"
else
    # Install via distro package manager (apt or dnf), including Microsoft repo.
    if command -v apt-get &>/dev/null; then
        # shellcheck disable=SC1091
        . /etc/os-release

        if [[ "${ID:-}" == "ubuntu" ]]; then
            repo_deb="https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"
        elif [[ "${ID:-}" == "debian" ]]; then
            repo_deb="https://packages.microsoft.com/config/debian/${VERSION_ID}/packages-microsoft-prod.deb"
        else
            echo "Unsupported apt-based distro for automatic .NET repo setup: ${ID:-unknown}" >&2
            exit 1
        fi

        if ! dpkg -s packages-microsoft-prod &>/dev/null; then
            tmp_pkg="/tmp/packages-microsoft-prod.deb"
            curl -fsSL "$repo_deb" -o "$tmp_pkg"
            sudo dpkg -i "$tmp_pkg"
            rm -f "$tmp_pkg"
        fi

        sudo apt-get update -qq
        sudo apt-get install -y -qq dotnet-sdk-9.0
        done_ ".NET SDK installed"
    elif command -v dnf &>/dev/null; then
        # shellcheck disable=SC1091
        . /etc/os-release

        if [[ "${ID:-}" == "fedora" ]]; then
            repo_rpm="https://packages.microsoft.com/config/fedora/${VERSION_ID}/packages-microsoft-prod.rpm"
        else
            major="${VERSION_ID%%.*}"
            repo_rpm="https://packages.microsoft.com/config/rhel/${major}/packages-microsoft-prod.rpm"
        fi

        if ! rpm -q packages-microsoft-prod &>/dev/null; then
            sudo dnf install -y "$repo_rpm"
        fi

        sudo dnf makecache -y
        sudo dnf install -y dotnet-sdk-9.0
        done_ ".NET SDK installed"
    else
        echo "Neither apt-get nor dnf is available. Cannot install .NET SDK automatically." >&2
        exit 1
    fi
fi

# ── Dotnet tools ────────────────────────────────────────────────────────────

step "Installing global dotnet tools"

if dotnet tool list -g 2>/dev/null | grep -q '^binloginsights.mcp '; then
    skip "dotnet tool binloginsights.mcp is already installed"
else
    dotnet tool install -g binloginsights.mcp
    done_ "dotnet tool binloginsights.mcp installed"
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

# No windbg on Linux
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
      1. Start Docker: sudo systemctl enable --now docker
      2. Run 'gh auth login' if not already authenticated
            3. Enable the Copilot plugins listed above
            4. Log out and back in if you were added to the docker group
EOF
