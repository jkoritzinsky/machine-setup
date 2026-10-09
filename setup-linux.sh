#!/usr/bin/env bash
# Machine setup script for Linux (apt/dnf based distros).
set -euo pipefail

step()  { printf '\n\033[36m>>> %s\033[0m\n' "$1"; }
done_() { printf '    \033[32m%s\033[0m\n' "$1"; }
skip()  { printf '    \033[33mSKIP: %s\033[0m\n' "$1"; }

# shellcheck disable=SC1091
. /etc/os-release

if command -v apt-get &>/dev/null; then
    pkg_mgr="apt"
elif command -v dnf &>/dev/null; then
    pkg_mgr="dnf"
else
    echo "Neither apt-get nor dnf is available. Cannot continue." >&2
    exit 1
fi

pkg_installed() {
    local pkg="$1"
    if [[ "$pkg_mgr" == "apt" ]]; then
        dpkg -s "$pkg" &>/dev/null
    else
        rpm -q "$pkg" &>/dev/null
    fi
}

pkg_update() {
    if [[ "$pkg_mgr" == "apt" ]]; then
        sudo apt-get update -qq
    else
        sudo dnf makecache -y >/dev/null
    fi
}

pkg_install() {
    if [[ "$pkg_mgr" == "apt" ]]; then
        sudo apt-get install -y -qq "$@"
    else
        sudo dnf install -y "$@"
    fi
}

# ── Tools ────────────────────────────────────────────────────────────────────

step "Installing base tools via $pkg_mgr"
pkg_update

for pkg in git jq ripgrep; do
    if pkg_installed "$pkg"; then
        skip "$pkg is already installed"
    else
        pkg_install "$pkg"
        done_ "$pkg installed"
    fi
done

# ── GitHub CLI ───────────────────────────────────────────────────────────────

step "Installing GitHub CLI (gh) via $pkg_mgr"

if command -v gh &>/dev/null; then
    skip "gh is already installed"
else
    if [[ "$pkg_mgr" == "apt" ]]; then
        sudo mkdir -p -m 755 /etc/apt/keyrings
        if [[ ! -f /etc/apt/keyrings/githubcli-archive-keyring.gpg ]]; then
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
            sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
        fi

        if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        fi

        pkg_update
        pkg_install gh
    else
        if ! sudo dnf repolist 2>/dev/null | grep -q '^gh-cli'; then
            pkg_install dnf-plugins-core
            sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
        fi

        pkg_update
        pkg_install gh
    fi

    done_ "gh installed"
fi

# ── Docker ───────────────────────────────────────────────────────────────────

step "Installing Docker via $pkg_mgr"

if command -v docker &>/dev/null; then
    skip "Docker is already installed"
else
    if [[ "$pkg_mgr" == "apt" ]]; then
        pkg_install docker.io
    else
        if [[ "${ID:-}" == "fedora" ]]; then
            pkg_install moby-engine
        else
            pkg_install dnf-plugins-core
            if ! sudo dnf repolist 2>/dev/null | grep -q '^docker-ce-stable'; then
                sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            fi
            pkg_update
            pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        fi
    fi

    sudo usermod -aG docker "$USER"
    done_ "Docker installed (log out and back in for group changes)"
fi

# ── .NET SDK ─────────────────────────────────────────────────────────────────

step "Installing .NET SDK via $pkg_mgr"

if command -v dotnet &>/dev/null; then
    skip ".NET SDK is already installed"
else
    if [[ "$pkg_mgr" == "apt" ]]; then
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

        pkg_update
        pkg_install dotnet-sdk-9.0
        done_ ".NET SDK installed"
    else
        if [[ "${ID:-}" == "fedora" ]]; then
            repo_rpm="https://packages.microsoft.com/config/fedora/${VERSION_ID}/packages-microsoft-prod.rpm"
        else
            major="${VERSION_ID%%.*}"
            repo_rpm="https://packages.microsoft.com/config/rhel/${major}/packages-microsoft-prod.rpm"
        fi

        if ! rpm -q packages-microsoft-prod &>/dev/null; then
            pkg_install "$repo_rpm"
        fi

        pkg_update
        pkg_install dotnet-sdk-9.0
        done_ ".NET SDK installed"
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

# ── Copilot CLI ──────────────────────────────────────────────────────────────

step "Installing Copilot CLI"

if gh extension list 2>/dev/null | grep -q '^gh-copilot\b'; then
    skip "Copilot CLI is already installed"
else
    gh extension install github/gh-copilot
    done_ "Copilot CLI installed"
fi

# ── Copilot plugins ─────────────────────────────────────────────────────────

step "Installing Copilot plugins"

if ! gh extension list 2>/dev/null | grep -q '^gh-copilot\b'; then
    skip "Copilot CLI not found; skipping Copilot plugin installation"
else
    run_copilot_cmd() {
        local label="$1"
        shift

        local output
        if output=$(gh copilot "$@" 2>&1); then
            done_ "$label"
        elif grep -qi "already" <<<"$output"; then
            skip "$label is already configured"
        else
            echo "$output" >&2
            return 1
        fi
    }

    run_copilot_cmd "Added marketplace jkoritzinsky/machine-setup" plugin marketplace add jkoritzinsky/machine-setup
    run_copilot_cmd "Added marketplace dotnet/arcade-skills" plugin marketplace add dotnet/arcade-skills
    run_copilot_cmd "Installed notification-tools@machine-setup" plugin install notification-tools@machine-setup
    run_copilot_cmd "Installed session-stacks@machine-setup" plugin install session-stacks@machine-setup
    run_copilot_cmd "Installed workiq@copilot-plugins" plugin install workiq@copilot-plugins
    run_copilot_cmd "Installed dotnet-dnceng@dotnet-arcade-skills" plugin install dotnet-dnceng@dotnet-arcade-skills
    run_copilot_cmd "Installed dotnet@awesome-copilot" plugin install dotnet@awesome-copilot
fi

# ── Done ─────────────────────────────────────────────────────────────────────

step "Setup complete!"
cat <<EOF
    Remaining manual steps:
      1. Start Docker: sudo systemctl enable --now docker
      2. Run 'gh auth login' if not already authenticated
      3. Log out and back in if you were added to the docker group
EOF
