# mysetup

Reproducible development environment setup. One command to go from a fresh machine to a fully configured workstation, server, or VPS.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/marcelaodev/mysetup/main/bootstrap.sh)
```

## Table of Contents

- [Overview](#overview)
- [Prerequisites: Bitwarden Vault Setup](#prerequisites-bitwarden-vault-setup)
- [Quick Start](#quick-start)
  - [Fresh Desktop/Laptop](#fresh-desktoplaptop)
  - [Fresh Server](#fresh-server)
  - [Fresh VPS](#fresh-vps)
- [Repository Structure](#repository-structure)
- [How It Works](#how-it-works)
- [Features In Detail](#features-in-detail)
  - [Shell (zsh)](#shell-zsh)
  - [Git](#git)
  - [Tmux](#tmux)
  - [Neovim (LazyVim)](#neovim-lazyvim)
  - [SSH Keys and Config](#ssh-keys-and-config)
  - [Package Management](#package-management)
  - [GNOME Extensions](#gnome-extensions)
  - [Browser Setup](#browser-setup)
  - [VPS Provisioning](#vps-provisioning)
- [Remote Access from Android](#remote-access-from-android)
- [Cross-Platform Support](#cross-platform-support)
- [Day-to-Day Usage](#day-to-day-usage)
- [Adding Your Own Customizations](#adding-your-own-customizations)
- [Troubleshooting](#troubleshooting)

---

## Overview

This repo uses [chezmoi](https://www.chezmoi.io/) to manage dotfiles and [Bitwarden](https://bitwarden.com/) to manage secrets. The architecture separates concerns:

- **`home/`** — chezmoi source directory (dotfiles, scripts, templates)
- **`vps/`** — standalone VPS provisioning (SSH hardening, Docker, firewall)
- **`browser/`** — DBeaver config generator
- **`bootstrap.sh`** — one-liner entry point for fresh machines

The `.chezmoiroot` file tells chezmoi to use `home/` as its source directory, so provisioning scripts and other non-dotfile content live cleanly at the repo root without interfering.

---

## Prerequisites: Bitwarden Vault Setup

Before running the bootstrap on any machine, you need these items in your Bitwarden vault. This is a **one-time setup**.

### 1. GitHub Identity

Create two **Secure Notes** in Bitwarden:

- **`github_name`** — Notes field: your full name (e.g. `Marcelo`)
- **`github_email`** — Notes field: your email address (e.g. `you@example.com`)

> These are used to populate `~/.gitconfig` automatically during setup.

### 2. SSH Keys

Generate two Ed25519 key pairs — one for GitHub, one for VPS access:

```bash
ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_github
ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_ed25519
```

#### `ssh-key-github` (GitHub)

Create a **Secure Note** in Bitwarden named exactly `ssh-key-github`:
- **Notes field**: paste the entire contents of `~/.ssh/id_github` (the private key), including the `-----BEGIN` and `-----END` lines
- **Custom field** named `public` (type: Text): paste the contents of `~/.ssh/id_github.pub`

Add the public key to your [GitHub SSH keys](https://github.com/settings/keys).

#### `ssh-key-ed25519` (VPS)

Create a **Secure Note** in Bitwarden named exactly `ssh-key-ed25519`:
- **Notes field**: paste the entire contents of `~/.ssh/id_ed25519` (the private key), including the `-----BEGIN` and `-----END` lines
- **Custom field** named `public` (type: Text): paste the contents of `~/.ssh/id_ed25519.pub`

### 3. Server Config — `server-config`

Create a **Secure Note** in Bitwarden named exactly `server-config` with two custom fields:
- `domain` (Text): your server's domain or IP, e.g. `myserver.example.com`
- `sshPort` (Text): your custom SSH port, e.g. `2222`

> This item is only used when machineType is `desktop` or `server`. You can skip it if you only use VPS provisioning.

### 4. VPS Credentials — `vps-credentials`

Create a **Secure Note** in Bitwarden named exactly `vps-credentials` with one custom field:
- `totp_secret` (Text): a base32 TOTP secret key for Google Authenticator

The SSH public key is pulled from the `ssh-key-ed25519` Bitwarden item (see above). No password is needed — authentication uses SSH key + TOTP.

To generate a TOTP secret, you can use:

```bash
# Generate a random base32 secret (26 chars)
head -c 20 /dev/urandom | base32
```

Save the generated secret in Bitwarden, then add it to your authenticator app (Google Authenticator, Authy, etc.) using manual entry.

> This item is only needed for VPS provisioning.

### 5. Cloudflare DNS — `cloudflare-dns`

Create a **Secure Note** in Bitwarden named exactly `cloudflare-dns` with two custom fields:
- `api_token` (Text): a Cloudflare API token with **Zone:DNS:Edit** permission
- `zone_id` (Text): the Cloudflare zone ID (found in the domain's overview page)

To create the API token, go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens) → Create Token → **Edit zone DNS** template → select your zone.

> This item is only needed for VPS provisioning. The provision script prompts you for the DNS record name (e.g. `vps.example.com`), then automatically creates or updates the A record to point to the VPS's public IP.

### 6. DBeaver Connections — `dbeaver-connections`

Create a **Secure Note** in Bitwarden named exactly `dbeaver-connections`. Paste a JSON array of connection definitions in the **Notes** field:

```json
[
  {
    "name": "VPS MySQL",
    "driver": "mysql8",
    "host": "localhost",
    "port": "3306",
    "database": "laravel",
    "user": "root",
    "password": "your-mysql-password",
    "ssh": {
      "host": "vps.example.com",
      "port": 2222,
      "user": "marcelo",
      "authType": "PUBLIC_KEY",
      "keyPath": "~/.ssh/id_ed25519"
    }
  },
  {
    "name": "Local PostgreSQL",
    "driver": "postgres-jdbc",
    "host": "localhost",
    "port": "5432",
    "database": "laravel",
    "user": "postgres",
    "password": "secret"
  }
]
```

**Supported fields:**

| Field | Required | Values |
|---|---|---|
| `name` | Yes | Display name in DBeaver |
| `driver` | Yes | `mysql8`, `postgres-jdbc`, or `mariaDB` |
| `host` | Yes | Database hostname |
| `port` | Yes | Database port |
| `database` | No | Database name |
| `user` | Yes | Database username |
| `password` | Yes | Database password |
| `ssh` | No | SSH tunnel config (see below) |
| `ssh.host` | Yes | SSH server hostname |
| `ssh.port` | No | SSH port (default: `22`) |
| `ssh.user` | Yes | SSH username |
| `ssh.authType` | No | `PUBLIC_KEY` (default) or `AGENT` |
| `ssh.keyPath` | No | Path to private key (`~` is expanded) |
| `ssh.implementation` | No | `sshj` (default, supports ed25519) or `jsch` |

> Credentials are encrypted using DBeaver's AES-192-CBC encryption and written to `credentials-config.json`. The setup script generates both `data-sources.json` and the encrypted credentials file.

### 7. Clipboard Favorites — `clipboard-favorites`

Create a **Secure Note** in Bitwarden named exactly `clipboard-favorites`. Paste a JSON array of strings in the **Notes** field:

```json
["frequently used snippet", "another pinned value", "email@example.com"]
```

> This item is only used on desktop machine types. The setup script loads these strings as pinned favorites in the Clipboard Indicator GNOME extension before it starts, so they're available immediately.

---

## Quick Start

### Fresh Desktop/Laptop

This is the primary use case — setting up a new Ubuntu or macOS workstation from scratch.

```bash
# Run the bootstrap (installs everything automatically)
bash <(curl -fsSL https://raw.githubusercontent.com/marcelaodev/mysetup/main/bootstrap.sh)
```

The bootstrap will:
1. Detect your OS (Ubuntu/macOS)
2. Install git, curl, jq, zsh
3. Install chezmoi and the Bitwarden CLI
4. Prompt you to log in to Bitwarden (master password)
5. Clone this repo to `~/mysetup`
6. Run `chezmoi init --apply`, which:
   - Asks you to choose machine type → select **desktop**
   - Fetches your name and email from Bitwarden (for git config)
   - Installs all packages from `packages.yaml` (including Docker CE)
   - Deploys all dotfiles (zsh, git, tmux, nvim, ssh)
   - Pulls external dependencies (oh-my-zsh, TPM)
   - Installs snap packages (nvim, Slack, DBeaver, VS Code)
   - Installs GNOME extensions + loads Clipboard Indicator favorites from Bitwarden
   - Configures Firefox extensions via enterprise policies
   - Configures DBeaver connections from Bitwarden

After it finishes, open a new terminal to start using zsh. The remaining manual steps are: sign into Firefox Sync, log into your services (Google, GitHub, Slack, etc.), and enable GNOME extensions if a logout/login is needed.

### Fresh Server

Same bootstrap command, but choose **server** when prompted:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/marcelaodev/mysetup/main/bootstrap.sh)
# When prompted for machine type → select "server"
```

Server mode installs common CLI tools and dotfiles (zsh, git, tmux) but skips desktop applications (Firefox, GNOME extensions, snap GUI apps) and Neovim config.

### Fresh VPS

VPS provisioning is a separate, standalone process — it doesn't use chezmoi. See [VPS Provisioning](#vps-provisioning) below.

---

## Repository Structure

```
mysetup/
├── .chezmoiroot                    # Points chezmoi to home/
├── bootstrap.sh                    # One-liner entry point
│
├── home/                           # chezmoi source directory
│   ├── .chezmoi.toml.tmpl         # Config template (machine type, bitwarden)
│   ├── .chezmoiignore             # Conditional file ignoring
│   ├── .chezmoiexternal.toml      # External git repos (oh-my-zsh, TPM)
│   ├── .chezmoidata/
│   │   └── packages.yaml          # Package lists per OS/machine type
│   ├── .chezmoiscripts/
│   │   ├── run_once_before_01-install-prerequisites.sh.tmpl
│   │   ├── run_onchange_after_10-install-packages.sh.tmpl
│   │   ├── run_onchange_after_20-install-snaps.sh.tmpl
│   │   ├── run_onchange_after_30-install-gnome-extensions.sh.tmpl
│   │   ├── run_once_after_40-install-tmux-plugins.sh.tmpl
│   │   ├── run_once_after_42-install-nvim-plugins.sh.tmpl
│   │   ├── run_once_after_50-setup-firefox-extensions.sh.tmpl
│   │   ├── run_once_after_55-setup-dbeaver.sh.tmpl
│   │   └── run_once_after_90-finalize.sh.tmpl
│   ├── dot_zshrc.tmpl             # → ~/.zshrc
│   ├── dot_gitconfig.tmpl         # → ~/.gitconfig
│   ├── dot_config/
│   │   ├── tmux/tmux.conf         # → ~/.config/tmux/tmux.conf
│   │   └── nvim/                  # → ~/.config/nvim/ (LazyVim)
│   └── private_dot_ssh/
│       ├── private_id_ed25519.tmpl    # → ~/.ssh/id_ed25519
│       ├── id_ed25519.pub.tmpl        # → ~/.ssh/id_ed25519.pub
│       └── config.tmpl                # → ~/.ssh/config
│
├── vps/
│   ├── provision.sh               # Standalone VPS setup script
│   ├── docker-compose.yml         # MySQL, Postgres, Laravel Sail
│   ├── Dockerfile.sail            # Laravel Sail app image
│   ├── supervisord.conf           # Supervisor config for Sail
│   └── configs/
│       ├── sshd_config            # Hardened SSH config
│       ├── jail.local             # Fail2ban config
│       └── pam-sshd              # PAM: password + TOTP
│
└── browser/
    └── dbeaver-setup.js           # Generates DBeaver config + encrypted credentials
```

---

## How It Works

### chezmoi Template System

Files ending in `.tmpl` are Go templates processed by chezmoi. They use data from:
- **`.chezmoi.toml.tmpl`** — defines `machineType` and Bitwarden integration; fetches name/email from vault
- **`.chezmoidata/packages.yaml`** — package lists accessible as `.linux`, `.darwin`, `.windows`
- **Built-in variables** — `.chezmoi.os` (`linux`, `darwin`), `.chezmoi.arch`, etc.

Files without `.tmpl` (like `tmux.conf`) are deployed as-is without template processing.

### chezmoi Naming Conventions

| Prefix/Name | Meaning |
|---|---|
| `dot_` | File starts with `.` (e.g. `dot_zshrc` → `.zshrc`) |
| `private_` | File permissions set to `0600` |
| `run_once_before_` | Script runs once, before applying files |
| `run_onchange_after_` | Script re-runs when its content (or hash comment) changes |
| `run_once_after_` | Script runs once, after applying files |
| `.tmpl` | Processed as a Go template |

### Bitwarden Integration

Secrets are never stored in the repo. chezmoi calls the Bitwarden CLI at apply time:
- `{{ (bitwarden "item" "ssh-key-ed25519").notes }}` — reads the Notes field
- `{{ (bitwardenFields "item" "server-config").domain.value }}` — reads a custom field

You must be logged in to Bitwarden (`bw login` or `bw unlock`) before running `chezmoi apply`. The bootstrap script handles this automatically.

Git config uses the `name` and `email` values fetched from Bitwarden (`github_name` and `github_email` items).

### Script Execution Order

chezmoi runs scripts in filename-sorted order. The numbering ensures correct sequencing:

1. `01-install-prerequisites` — zsh, curl, jq, git (runs **once**, **before** files)
2. `10-install-packages` — apt/brew packages (runs **on change** to packages.yaml)
3. `20-install-snaps` — snap packages, Linux desktop only (runs **on change**)
4. `30-install-gnome-extensions` — GNOME extensions + Clipboard Indicator favorites from Bitwarden, Linux desktop only (runs **on change**)
5. `40-install-tmux-plugins` — runs TPM install script (runs **once**)
6. `42-install-nvim-plugins` — LazyVim sync + Treesitter + Mason LSPs, headless (runs **once**)
7. `50-setup-firefox-extensions` — installs Firefox extensions via enterprise policies, desktop only (runs **once**)
8. `55-setup-dbeaver` — configures DBeaver connections from Bitwarden, desktop only (runs **once**)
9. `90-finalize` — prints completion message (runs **once**, **after** files)

---

## Features In Detail

### Shell (zsh)

**File**: `home/dot_zshrc.tmpl` → `~/.zshrc`

Oh-My-Zsh with the `robbyrussell` theme and these plugins:
- `git` — Git aliases and completions
- `zsh-autosuggestions` — fish-like suggestions as you type
- `zsh-syntax-highlighting` — real-time command highlighting
- `docker` / `docker-compose` — Docker completions
- `kubectl` — Kubernetes completions
- `fzf` — fuzzy finder integration

**Aliases:**

| Alias | Command | Description |
|---|---|---|
| `ll` | `ls -lAh` | Long list with hidden files |
| `v` / `vim` | `nvim` | Neovim |
| `g` | `git` | Short git |
| `gs` | `git status` | Status |
| `gd` | `git diff` | Diff |
| `gc` | `git commit` | Commit |
| `gp` | `git push` | Push |
| `gl` | `git log --oneline --graph` | Log graph |
| `dc` | `docker compose` | Docker compose |
| `k` | `kubectl` | Kubernetes |
| `open` | `xdg-open` | Open files (Linux only) |
| `pbcopy` | `xclip -selection clipboard` | Copy to clipboard (Linux only) |
| `pbpaste` | `xclip -selection clipboard -o` | Paste from clipboard (Linux only) |

**Other settings:**
- Vi keybindings in the shell (`bindkey -v`)
- 50,000 lines of history with deduplication
- `Ctrl-R` for reverse history search
- Loads `~/.zshrc.local` for machine-specific overrides

**Local overrides**: Create `~/.zshrc.local` on any machine to add settings that shouldn't be in the repo (work-specific aliases, tokens, etc.). This file is sourced automatically and is not managed by chezmoi.

### Git

**File**: `home/dot_gitconfig.tmpl` → `~/.gitconfig`

Git configuration with identity from Bitwarden:
- **Name**: from `github_name` Bitwarden item (Notes field)
- **Email**: from `github_email` Bitwarden item (Notes field)
- **Editor**: nvim
- **Pager**: [delta](https://github.com/dandavison/delta) with side-by-side diffs and line numbers
- **Pull**: rebase by default
- **Push**: auto-setup remote tracking
- **Merge**: diff3 conflict style
- **SSH**: rewrites `https://github.com/` to `git@github.com:` for SSH-based auth

**Aliases:**

| Alias | Command |
|---|---|
| `git co` | `checkout` |
| `git br` | `branch` |
| `git ci` | `commit` |
| `git st` | `status` |
| `git lg` | `log --oneline --graph --decorate --all` |
| `git unstage` | `reset HEAD --` |
| `git last` | `log -1 HEAD` |

### Tmux

**File**: `home/dot_config/tmux/tmux.conf` → `~/.config/tmux/tmux.conf`

**Prefix**: `Ctrl-a` (not the default `Ctrl-b` — easier to reach)

**Key bindings:**

| Key | Action |
|---|---|
| `Ctrl-a \|` | Split pane vertically |
| `Ctrl-a -` | Split pane horizontally |
| `Ctrl-a h/j/k/l` | Navigate panes (vim-style) |
| `Ctrl-a H/J/K/L` | Resize panes |
| `Ctrl-a Ctrl-h` | Previous window |
| `Ctrl-a Ctrl-l` | Next window |
| `Ctrl-a r` | Reload tmux config |
| `Ctrl-a I` | Install TPM plugins (first run) |
| `Ctrl-a [` | Enter copy mode (vi keys) |

**Copy mode** (vi-style): press `v` to start selection, `y` to copy to system clipboard.

**Plugins** (via TPM):
- **tmux-sensible** — sensible defaults
- **tmux-resurrect** — save/restore sessions across tmux restarts
- **tmux-continuum** — automatic session saving + auto-restore on tmux start

**First-time setup**: Plugins are installed automatically by chezmoi via TPM's `install_plugins.sh` script. No manual `Ctrl-a I` needed.

**Session persistence**: With resurrect + continuum, your tmux sessions (windows, panes, working directories) survive system reboots. Sessions are saved automatically every 15 minutes and restored when tmux starts.

### Neovim (LazyVim)

**Files**: `home/dot_config/nvim/` → `~/.config/nvim/`

Built on [LazyVim](https://www.lazyvim.org/) — a full IDE experience out of the box. The config follows the official LazyVim starter structure:

```
nvim/
├── init.lua                  # Bootstraps lazy.nvim, loads config
└── lua/
    ├── config/
    │   ├── lazy.lua          # lazy.nvim setup + LazyVim import
    │   ├── options.lua       # Editor options
    │   ├── keymaps.lua       # Custom keybindings
    │   └── autocmds.lua      # Auto-commands
    └── plugins/
        ├── colorscheme.lua   # Catppuccin Mocha
        ├── editor.lua        # Neo-tree, Telescope, Gitsigns, Which-key
        └── coding.lua        # Treesitter, LSP, formatting
```

On first launch, lazy.nvim bootstraps itself, then downloads and installs LazyVim and all configured plugins automatically.

**Colorscheme**: Catppuccin Mocha

**Key bindings:**

| Key | Mode | Action |
|---|---|---|
| `Ctrl-h/j/k/l` | Normal | Navigate between windows |
| `J` / `K` | Visual | Move selected lines down/up |
| `Ctrl-d` / `Ctrl-u` | Normal | Scroll half-page (cursor stays centered) |
| `<leader>p` | Visual | Paste without losing register contents |
| `<leader>w` | Normal | Quick save |
| `Esc` | Normal | Clear search highlights |

> `<leader>` is `Space` (LazyVim default).

**Editor plugins:**
- **Neo-tree** — file explorer (shows dotfiles and gitignored files)
- **Telescope** — fuzzy finder for files, grep, buffers, etc.
- **Gitsigns** — git diff signs in the gutter + current line blame
- **Which-key** — shows available keybindings as you type
- **mini.surround** — add/change/delete surrounding characters
- **mini.comment** — toggle comments with `gc`

**Coding plugins:**
- **Treesitter** — syntax highlighting for 18 languages (bash, css, dockerfile, go, html, javascript, json, lua, markdown, python, regex, sql, toml, tsx, typescript, vim, vimdoc, yaml)
- **LSP servers** — lua_ls, pyright, ts_ls, gopls (install via `:Mason`)
- **Formatting** (via conform.nvim) — auto-format on save:

| Language | Formatter |
|---|---|
| Lua | stylua |
| Python | ruff_format |
| JS/TS/JSON/YAML/Markdown | prettierd |
| Go | gofumpt |
| Shell | shfmt |

**Autocmds:**
- Highlight yanked text briefly
- Auto-resize splits when terminal resizes
- Return to last edit position when reopening a file
- Strip trailing whitespace on save

**First-time setup**: Plugins, Treesitter parsers, and Mason LSP servers are installed automatically by chezmoi via `nvim --headless`. No manual setup needed.

**Adding plugins**: Create a new file in `home/dot_config/nvim/lua/plugins/` returning a Lazy.nvim plugin spec. chezmoi will deploy it on next `chezmoi apply`.

### SSH Keys and Config

**Files**: `home/private_dot_ssh/` → `~/.ssh/`

- **GitHub key** (`id_github`): pulled from Bitwarden `ssh-key-github`. Used exclusively for GitHub.
- **VPS key** (`id_ed25519`): pulled from Bitwarden `ssh-key-ed25519`. Used for VPS/server access.
- Both deployed with `0600` permissions (chezmoi `private_` prefix).
- **SSH config**: GitHub uses the GitHub key; desktop/server machine types get a `myserver` host alias using the VPS key.

**Usage after setup:**

```bash
# GitHub (works immediately — key is deployed)
git clone git@github.com:marcelaodev/some-repo.git

# Server access (desktop/server machine types)
ssh myserver
```

### Package Management

**File**: `home/.chezmoidata/packages.yaml`

Packages are declared in YAML and installed automatically by chezmoi scripts. The scripts use a SHA-256 hash of `packages.yaml` as a change trigger — they re-run whenever you modify the package list.

**Linux (apt) — common** (all machine types):
build-essential, curl, wget, git, jq, zsh, tmux, fzf, ripgrep, fd-find, bat, htop, unzip, xclip, git-delta, python3, python3-pip, python3-venv, nodejs, npm, golang-go

**Linux — Docker** (all machine types):
Docker Engine CE, containerd, docker-compose-plugin (installed from Docker's official apt repository)

**Linux (apt) — desktop only:**
firefox, chromium-browser, gnome-tweaks, vlc

**Linux (snap) — desktop only:**
nvim (classic), slack (classic), dbeaver-ce, code (classic)

**macOS (brew):**
git, curl, jq, zsh, tmux, fzf, ripgrep, fd, bat, htop, neovim, node, go, python, git-delta

**macOS (cask):**
firefox, iterm2, visual-studio-code, docker, rectangle, raycast, slack, dbeaver-community

**Windows (winget):**
Firefox, VS Code, Docker Desktop, Slack, DBeaver

**Adding a package**: Edit `home/.chezmoidata/packages.yaml`, add the package to the appropriate list, then run `chezmoi apply`. The install script detects the change and runs automatically.

### GNOME Extensions

**File**: `home/.chezmoiscripts/run_onchange_after_30-install-gnome-extensions.sh.tmpl`

Installed only on Linux desktop:
- **Clipboard Indicator** (extension 779) — clipboard history manager with pinned favorites
- **Stopwatch** (extension 5796) — minimal stopwatch in the top bar
- **Cronomix** (extension 6003) — stopwatch, timer, pomodoro, alarm, and time tracker

Extensions are installed via `gnome-extensions-cli` (`gext`), which is installed via pipx with `--system-site-packages` (required for PyGObject access). Dependencies `python3-gi` and `gir1.2-gtk-3.0` are installed automatically by the script.

**Clipboard Indicator favorites**: Pinned strings are loaded from the `clipboard-favorites` Bitwarden item (see [Prerequisites](#7-clipboard-favorites--clipboard-favorites)) and written to `~/.cache/clipboard-indicator@tudmotu.com/registry.txt` before the extension loads, so they're immediately available.

**Adding extensions**: Add the extension ID number to `packages.yaml` under `linux.gnome_extensions.desktop`, then `chezmoi apply`.

**Note**: Extensions may require a logout/login to fully activate after installation.

### Browser Setup

**Firefox extensions** are installed automatically via [Firefox enterprise policies](https://mozilla.github.io/policy-templates/). The chezmoi script writes a `policies.json` file that tells Firefox to force-install extensions on next launch — no profile manipulation or browser automation needed.

**Installed extensions:**

| Extension | Description |
|---|---|
| Bitwarden | Password manager |
| Adblock Plus | Ad blocker |
| Bookmark Manager and Viewer | Enhanced bookmarks |
| GNOME Shell Integration | GNOME extensions from Firefox (Linux only) |
| Vimium | Vim keybindings for the browser |
| YouTube Playlist Duration | Shows total playlist duration |

**How it works**: The script writes `/etc/firefox/policies/policies.json` (Linux) or `/Library/Application Support/Mozilla/policies/policies.json` (macOS). Firefox reads this file on launch and auto-installs the listed extensions. No manual steps required.

**Firefox Sync**: Sign into Firefox Sync manually after first launch to restore bookmarks, history, and saved passwords across machines.

### VPS Provisioning

**Files**: `vps/provision.sh`, `vps/configs/*`, `vps/docker-compose.yml`, `vps/Dockerfile.sail`

This is a **standalone** script — it does NOT use chezmoi. It's designed to run on a fresh Ubuntu VPS from any provider (DigitalOcean, Hetzner, Vultr, Linode, etc.).

The script pulls the user password and TOTP secret from Bitwarden automatically — no manual password entry or QR code scanning required.

#### Bitwarden Setup for VPS

Before running `provision.sh`, create the `vps-credentials` item in Bitwarden (see [Prerequisites](#4-vps-credentials--vps-credentials)).

#### Running It

SSH into your fresh VPS as root, then:

```bash
# Clone and run
git clone https://github.com/marcelaodev/mysetup.git
cd mysetup
sudo bash vps/provision.sh

# Custom SSH port
sudo SSH_PORT=3333 bash vps/provision.sh
```

The script will prompt for your Bitwarden master password to retrieve the VPS credentials.

#### What It Does

1. **System update** — `apt upgrade` and installs base packages
2. **Bitwarden CLI** — installs `bw` and prompts you to log in
3. **Credential retrieval** — pulls `totp_secret` from `vps-credentials` and SSH public key from `ssh-key-ed25519`
4. **User creation** — creates user `marcelo` with sudo, sets zsh as shell, configures SSH authorized key
5. **TOTP setup** — configures Google Authenticator automatically using the Bitwarden-stored TOTP secret
6. **SSH hardening**:
   - Custom port (default 2222, override with `SSH_PORT`)
   - Root login disabled
   - **Two-factor: SSH key + TOTP** (Google Authenticator)
   - X11/TCP/Agent forwarding disabled
   - Max 3 auth attempts, 3 concurrent sessions
7. **Firewall (UFW)** — deny all incoming, allow SSH port + 80 + 443
8. **Fail2ban** — bans IPs after 3 failed SSH attempts for 1 hour
9. **Docker** — installs Docker Engine, adds user to docker group
10. **Docker images** — pulls MySQL 8 and PostgreSQL 16 images; copies Sail Dockerfile for later use
11. **Cloudflare DNS** — prompts for record name, detects VPS public IP, creates/updates the A record via Cloudflare API

Sensitive variables (`TOTP_SECRET`, `SSH_PUBLIC_KEY`, `BW_SESSION`) are cleared from memory after use.

#### SSH Login Flow

After setup, connecting to the VPS looks like this:

```
$ ssh marcelo@myserver.example.com -p 2222
Verification code: 123456
Welcome to Ubuntu...
```

Your SSH key authenticates first (automatically), then you enter the 6-digit TOTP code from your authenticator app.

#### Docker Services

The compose stack includes three services for Laravel development:

| Service | Image | Port | Description |
|---|---|---|---|
| MySQL 8 | `mysql:8` | 127.0.0.1:3306 | Primary database |
| PostgreSQL 16 | `postgres:16` | 127.0.0.1:5432 | Alternative database |
| Laravel Sail | `sail-8.4/app` (built) | 127.0.0.1:8000 | PHP 8.4 + Node 20 + Composer |

All ports are bound to localhost only (not publicly accessible).

**Deploying a Laravel project:**

```bash
# On the VPS, as marcelo
cd ~/docker

# Clone your Laravel project into the app volume or mount it
git clone git@github.com:marcelaodev/my-laravel-app.git app

# Create .env with database credentials
cat > .env <<EOF
MYSQL_ROOT_PASSWORD=your-secure-password
MYSQL_DATABASE=laravel
POSTGRES_PASSWORD=your-secure-password
POSTGRES_DB=laravel
EOF

# Build the Sail image and start everything
docker compose up -d --build
```

Data persists in Docker volumes (`mysql_data`, `postgres_data`, `app_data`).

#### Switching VPS Providers

The VPS is designed to be disposable:

1. Create a new VPS with a new provider
2. Run `provision.sh` on it (Bitwarden handles credentials + DNS automatically)
3. Destroy the old VPS

All state lives in the Bitwarden vault and this repo — nothing unique exists only on the VPS. The same password and TOTP secret are reused across VPS instances.

#### Post-Provisioning Security

After verifying everything works:

```bash
# Remove passwordless sudo (require password for sudo)
sudo rm /etc/sudoers.d/marcelo
```

---

## Remote Access from Android

The VPS is your portable dev environment. Access it from any device, including phones:

1. Install **Termux** or **JuiceSSH** on your Android device
2. Connect: `ssh marcelo@myserver.example.com -p 2222`
3. Enter your password (from Bitwarden), then your TOTP code
4. You land in a tmux session — persistent even if you disconnect
5. Run nvim inside tmux for a full development environment

**Tips:**
- Use `tmux attach` to reconnect to an existing session after disconnecting
- `Ctrl-a d` to detach from tmux without killing the session
- Works from any device with an SSH client — no chezmoi needed on the client

---

## Cross-Platform Support

### Linux (Ubuntu)

Primary platform. Everything works out of the box via the bootstrap script.

### macOS

Fully supported. The bootstrap and chezmoi templates detect macOS and:
- Install Homebrew (if not present)
- Use `brew install` / `brew install --cask` instead of apt/snap
- Skip Linux-specific features (GNOME extensions, snap packages)
- Set up Homebrew shell environment in `.zshrc`
- Skip `xclip` aliases (macOS has native `pbcopy`/`pbpaste`)

### Windows (via WSL2)

Run the bootstrap inside a WSL2 Ubuntu instance — it behaves like regular Linux. Native Windows apps are listed in `packages.yaml` under `windows.winget` for manual installation:

```powershell
# In PowerShell (not WSL)
winget install Mozilla.Firefox
winget install Microsoft.VisualStudioCode
winget install Docker.DockerDesktop
winget install SlackTechnologies.Slack
winget install dbeaver.dbeaver
```

---

## Day-to-Day Usage

### Checking What Would Change

```bash
# See what chezmoi would do (diff)
chezmoi diff

# Dry run — show what would be applied, without doing it
chezmoi apply -n -v

# Apply changes
chezmoi apply -v
```

### Editing Managed Files

You can edit dotfiles in two ways:

```bash
# Option 1: Edit the source directly in ~/mysetup/home/, then apply
vim ~/mysetup/home/dot_zshrc.tmpl
chezmoi apply

# Option 2: Use chezmoi edit (opens the source file for the given target)
chezmoi edit ~/.zshrc
chezmoi apply
```

### Adding a New Dotfile

```bash
# Tell chezmoi to manage an existing file
chezmoi add ~/.some-config

# This copies it into ~/mysetup/home/ with the correct chezmoi naming
# Then commit and push
```

### Updating After a Repo Change

If you pull updates from the remote:

```bash
cd ~/mysetup
git pull
chezmoi apply -v
```

### Re-running Install Scripts

The `run_onchange_after_*` scripts track changes via a hash comment. To force a re-run:

```bash
# Edit packages.yaml (even a whitespace change triggers re-run)
chezmoi apply
```

The `run_once_*` scripts only run once per machine. To re-run them:

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

---

## Adding Your Own Customizations

### New Package

Edit `home/.chezmoidata/packages.yaml`:

```yaml
linux:
  apt:
    common:
      - existing-package
      - your-new-package   # Add here
```

Then `chezmoi apply`.

### New Dotfile

```bash
# If the file already exists
chezmoi add ~/.your-config

# If you want to create a template (with conditional logic)
# Create it manually in ~/mysetup/home/ with chezmoi naming:
#   dot_your-config.tmpl
```

### New Neovim Plugin

Create `home/dot_config/nvim/lua/plugins/your-plugin.lua`:

```lua
return {
  {
    "author/plugin-name",
    opts = {
      -- your config
    },
  },
}
```

### New Tmux Plugin

Add to the plugins section in `home/dot_config/tmux/tmux.conf`:

```
set -g @plugin 'author/plugin-name'
```

Then `chezmoi apply`. The plugin will be installed automatically on next `chezmoi apply` run (or manually via `~/.tmux/plugins/tpm/scripts/install_plugins.sh`).

### New zsh Plugin

1. Add the plugin repo to `home/.chezmoiexternal.toml`:

```toml
[".oh-my-zsh/custom/plugins/your-plugin"]
  type = "git-repo"
  url = "https://github.com/author/your-plugin.git"
  refreshPeriod = "168h"
```

2. Add the plugin name to the `plugins=()` array in `home/dot_zshrc.tmpl`.

3. Run `chezmoi apply`.

---

## Troubleshooting

### Bitwarden errors during chezmoi apply

```
error: bitwarden: ...
```

Make sure Bitwarden is unlocked:

```bash
export BW_SESSION=$(bw unlock --raw)
```

Or if not logged in yet:

```bash
export BW_SESSION=$(bw login --raw)
```

### chezmoi apply fails with template errors

Run in verbose mode to see which template is failing:

```bash
chezmoi apply -v --debug
```

Check that the Bitwarden items exist with the correct names and field names (see [Prerequisites](#prerequisites-bitwarden-vault-setup)).

### SSH key permissions

chezmoi handles this automatically via the `private_` prefix (sets `0600`). If you see permission errors:

```bash
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
chmod 644 ~/.ssh/config
```

### Tmux plugins not loading

Press `Ctrl-a I` (capital I) to install TPM plugins. If TPM itself isn't present:

```bash
chezmoi apply  # Re-applies external deps including TPM
```

### Neovim errors on first launch

LazyVim downloads plugins on first open — this requires internet access. If plugins fail:

```bash
# Inside nvim
:Lazy sync
```

### VPS: Bitwarden login fails during provisioning

Make sure you can reach Bitwarden's servers from the VPS. If the VPS has strict outbound rules, you may need to allow HTTPS traffic first.

If you already have a `BW_SESSION`, you can pass it as an environment variable:

```bash
sudo BW_SESSION="your-session-key" bash vps/provision.sh
```

### VPS: Can't SSH after provisioning

1. Check the port: `ssh -p 2222 marcelo@your-ip` (default port is 2222, not 22)
2. Check UFW: `sudo ufw status` — SSH port must be allowed
3. Check sshd: `sudo systemctl status sshd`
4. Check fail2ban: `sudo fail2ban-client status sshd` — your IP might be banned
5. Unban: `sudo fail2ban-client set sshd unbanip YOUR_IP`

### VPS: TOTP not working

Verify the `.google_authenticator` file exists for the user:

```bash
ls -la /home/marcelo/.google_authenticator
```

Check that the PAM config is correct:

```bash
cat /etc/pam.d/sshd  # Should have pam_unix.so + pam_google_authenticator.so
```

Check that sshd is configured for challenge-response:

```bash
grep -E 'ChallengeResponse|AuthenticationMethods|UsePAM' /etc/ssh/sshd_config
```

Make sure the TOTP secret in your authenticator app matches the one in Bitwarden (`vps-credentials` → `totp_secret` field).

### Resetting chezmoi state

If things get out of sync:

```bash
# See what chezmoi thinks the state is
chezmoi status

# Re-initialize (re-prompts for machine type, email)
chezmoi init --source=$HOME/mysetup

# Nuclear option: remove chezmoi state and re-apply
rm -rf ~/.config/chezmoi ~/.local/share/chezmoi
chezmoi init --source=$HOME/mysetup --apply
```
