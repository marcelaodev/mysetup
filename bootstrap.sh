#!/bin/bash
# bootstrap.sh — entry point for fresh machines
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/marcelaodev/mysetup/main/bootstrap.sh)
set -euo pipefail

REPO="https://github.com/marcelaodev/mysetup.git"
SETUP_DIR="$HOME/mysetup"

echo "========================================"
echo "  mysetup — Reproducible Environment"
echo "========================================"
echo ""

# ---------- Phase 1: Detect OS and install basics ----------
echo "==> Phase 1: Detecting OS and installing basics..."

if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS="linux"
  DISTRO="$ID"
  echo "  Detected: Linux ($DISTRO)"
elif [ "$(uname)" = "Darwin" ]; then
  OS="darwin"
  echo "  Detected: macOS"
else
  echo "ERROR: Unsupported OS"
  exit 1
fi

if [ "$OS" = "linux" ]; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq git curl jq zsh
elif [ "$OS" = "darwin" ]; then
  if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  brew install git curl jq zsh
fi

# ---------- Phase 2: Install chezmoi + Bitwarden CLI ----------
echo ""
echo "==> Phase 2: Installing chezmoi and Bitwarden CLI..."

# Install chezmoi
if ! command -v chezmoi &>/dev/null; then
  echo "  Installing chezmoi..."
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
fi

# Install Bitwarden CLI
if ! command -v bw &>/dev/null; then
  echo "  Installing Bitwarden CLI..."
  if [ "$OS" = "linux" ]; then
    curl -fsSL "https://vault.bitwarden.com/download/?app=cli&platform=linux" -o /tmp/bw.zip
    unzip -o /tmp/bw.zip -d /tmp
    sudo install -m 755 /tmp/bw /usr/local/bin/bw
    rm -f /tmp/bw /tmp/bw.zip
  elif [ "$OS" = "darwin" ]; then
    brew install bitwarden-cli
  fi
fi

# ---------- Phase 3: Bitwarden login ----------
echo ""
echo "==> Phase 3: Bitwarden login..."
echo "  Please enter your Bitwarden credentials."

if [ -z "${BW_SESSION:-}" ]; then
  if bw status | jq -r '.status' | grep -q "unauthenticated"; then
    BW_SESSION=$(bw login --raw)
  else
    BW_SESSION=$(bw unlock --raw)
  fi
  export BW_SESSION
fi

echo "  Bitwarden unlocked."

# ---------- Phase 4: Clone repo and apply chezmoi ----------
echo ""
echo "==> Phase 4: Setting up dotfiles..."

if [ ! -d "$SETUP_DIR" ]; then
  echo "  Cloning repository..."
  git clone "$REPO" "$SETUP_DIR"
else
  echo "  Repository already exists, pulling latest..."
  git -C "$SETUP_DIR" pull --ff-only
fi

echo "  Applying chezmoi..."
chezmoi init --source="$SETUP_DIR" --apply

# ---------- Phase 5: Fetch update-ip script from Bitwarden ----------
echo ""
echo "==> Phase 5: Fetching update-ip script from Bitwarden..."
bw get notes "update-ip-script" --session "$BW_SESSION" > "$HOME/updateip.sh"
chmod +x "$HOME/updateip.sh"
echo "  Written to $HOME/updateip.sh"

echo ""
echo "========================================"
echo "  Setup complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (zsh is now your default shell)"
echo "  2. Open Firefox and sign in to Firefox Sync"
echo "  3. Login to Google, GitHub, Drive, Slack, Outlook, Facebook, Instagram, TikTok, Substack, FreshRelease, FreshDesk, AWS"
echo "  4. Enable Clipboard and Stopwatch GNOME indicators (may need log out/in)"
echo "  5. Configure DBeaver connections and sign in to Slack"