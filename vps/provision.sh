#!/bin/bash
# vps/provision.sh — standalone idempotent VPS provisioning
# Usage: git clone https://github.com/marcelaodev/mysetup.git && cd mysetup && sudo bash vps/provision.sh
set -euo pipefail

SSH_PORT="${SSH_PORT:-2222}"
USERNAME="marcelo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  VPS Provisioning"
echo "========================================"

# ---------- System update ----------
echo ""
echo "==> Updating system..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl wget git jq unzip \
  ufw fail2ban \
  zsh tmux neovim \
  libpam-google-authenticator

# ---------- Install Bitwarden CLI ----------
echo ""
echo "==> Installing Bitwarden CLI..."
if ! command -v bw &>/dev/null; then
  curl -fsSL "https://vault.bitwarden.com/download/?app=cli&platform=linux" -o /tmp/bw.zip
  unzip -o /tmp/bw.zip -d /tmp
  install -m 755 /tmp/bw /usr/local/bin/bw
  rm -f /tmp/bw /tmp/bw.zip
  echo "  Bitwarden CLI installed."
else
  echo "  Bitwarden CLI already installed."
fi

# ---------- Bitwarden login ----------
echo ""
echo "==> Logging in to Bitwarden to retrieve VPS credentials..."
echo "  Please enter your Bitwarden master password."

if [ -z "${BW_SESSION:-}" ]; then
  if bw status 2>/dev/null | jq -r '.status' | grep -q "unauthenticated"; then
    BW_SESSION=$(bw login --raw)
  else
    BW_SESSION=$(bw unlock --raw)
  fi
  export BW_SESSION
fi

echo "  Bitwarden unlocked."

# ---------- Retrieve credentials from Bitwarden ----------
echo ""
echo "==> Retrieving VPS credentials from Bitwarden..."

TOTP_SECRET=$(bw get item vps-credentials --session "$BW_SESSION" | jq -r '.fields[] | select(.name == "totp_secret") | .value')
SSH_PUBLIC_KEY=$(bw get item ssh-key-ed25519 --session "$BW_SESSION" | jq -r '.fields[] | select(.name == "public") | .value')

if [ -z "$TOTP_SECRET" ] || [ "$TOTP_SECRET" = "null" ]; then
  echo "ERROR: Could not retrieve 'totp_secret' field from Bitwarden item 'vps-credentials'."
  echo "  Create a Secure Note named 'vps-credentials' with a custom field:"
  echo "    - totp_secret (Text): the TOTP secret key (base32)"
  exit 1
fi

if [ -z "$SSH_PUBLIC_KEY" ] || [ "$SSH_PUBLIC_KEY" = "null" ]; then
  echo "ERROR: Could not retrieve 'public' field from Bitwarden item 'ssh-key-ed25519'."
  echo "  Create a Secure Note named 'ssh-key-ed25519' with a custom field:"
  echo "    - public (Text): your SSH ed25519 public key"
  exit 1
fi

echo "  Credentials retrieved."

# ---------- Create user ----------
echo ""
echo "==> Setting up user: $USERNAME..."
if ! id "$USERNAME" &>/dev/null; then
  adduser --disabled-password --gecos "" "$USERNAME"
  echo "  Created user $USERNAME"
fi

# Add to sudo group
usermod -aG sudo "$USERNAME"

# Set zsh as default shell
chsh -s "$(which zsh)" "$USERNAME"

# Allow sudo without password for initial setup
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
chmod 440 "/etc/sudoers.d/$USERNAME"

# Set up SSH authorized key
SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
echo "$SSH_PUBLIC_KEY" > "$SSH_DIR/authorized_keys"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
echo "  SSH public key configured."

# ---------- TOTP setup ----------
echo ""
echo "==> Configuring TOTP from Bitwarden..."

TOTP_DIR="/home/$USERNAME"
sudo -u "$USERNAME" google-authenticator \
  -t -d -f -r 3 -R 30 -w 3 \
  -s "$TOTP_DIR/.google_authenticator" \
  --secret="$TOTP_SECRET" \
  --no-confirm

echo "  TOTP configured. Add this secret to your authenticator app: $TOTP_SECRET"

# ---------- SSH hardening ----------
echo ""
echo "==> Configuring SSH (port $SSH_PORT, SSH key + TOTP)..."

# Copy sshd_config
if [ -f "$SCRIPT_DIR/configs/sshd_config" ]; then
  cp "$SCRIPT_DIR/configs/sshd_config" /etc/ssh/sshd_config
else
  cat > /etc/ssh/sshd_config <<'SSHD'
Port 2222
Protocol 2
PermitRootLogin no
MaxAuthTries 3
MaxSessions 3
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication yes
AuthenticationMethods publickey,keyboard-interactive
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
SSHD
fi

# Replace port in sshd_config
sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config

# Copy PAM config
if [ -f "$SCRIPT_DIR/configs/pam-sshd" ]; then
  cp "$SCRIPT_DIR/configs/pam-sshd" /etc/pam.d/sshd
else
  cat > /etc/pam.d/sshd <<'PAM'
# PAM config for SSH: TOTP only (SSH key verified by sshd)
auth required pam_google_authenticator.so nullok
account required pam_nologin.so
account include common-account
session required pam_loginuid.so
session optional pam_keyinit.so force revoke
session include common-session
session optional pam_motd.so motd=/run/motd.dynamic
session optional pam_motd.so noupdate
session optional pam_mail.so standard noenv
PAM
fi

systemctl restart sshd

# ---------- UFW Firewall ----------
echo ""
echo "==> Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw --force enable
echo "  Firewall enabled."

# ---------- Fail2ban ----------
echo ""
echo "==> Configuring fail2ban..."

if [ -f "$SCRIPT_DIR/configs/jail.local" ]; then
  cp "$SCRIPT_DIR/configs/jail.local" /etc/fail2ban/jail.local
else
  cat > /etc/fail2ban/jail.local <<JAIL
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
JAIL
fi

systemctl enable fail2ban
systemctl restart fail2ban
echo "  Fail2ban configured."

# ---------- Docker ----------
echo ""
echo "==> Installing Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  usermod -aG docker "$USERNAME"
  echo "  Docker installed."
else
  echo "  Docker already installed."
fi

# ---------- Docker Compose stack ----------
echo ""
echo "==> Deploying Docker Compose stack..."
COMPOSE_DIR="/home/$USERNAME/docker"
mkdir -p "$COMPOSE_DIR"

if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
  cp "$SCRIPT_DIR/docker-compose.yml" "$COMPOSE_DIR/docker-compose.yml"
fi

if [ -f "$SCRIPT_DIR/Dockerfile.sail" ]; then
  cp "$SCRIPT_DIR/Dockerfile.sail" "$COMPOSE_DIR/Dockerfile.sail"
fi

if [ -f "$SCRIPT_DIR/supervisord.conf" ]; then
  cp "$SCRIPT_DIR/supervisord.conf" "$COMPOSE_DIR/supervisord.conf"
fi

chown -R "$USERNAME:$USERNAME" "$COMPOSE_DIR"

# Pull base images (build Sail image later when a Laravel project is deployed)
echo "  Pulling database images..."
docker pull mysql:8
docker pull postgres:16

echo "  Database images pulled. Sail image will be built when a Laravel project is deployed."

# ---------- Cloudflare DNS ----------
echo ""
echo "==> Updating Cloudflare DNS..."

CF_API_TOKEN=$(bw get item cloudflare-dns --session "$BW_SESSION" | jq -r '.fields[] | select(.name == "api_token") | .value')
CF_ZONE_ID=$(bw get item cloudflare-dns --session "$BW_SESSION" | jq -r '.fields[] | select(.name == "zone_id") | .value')

if [ -z "$CF_API_TOKEN" ] || [ "$CF_API_TOKEN" = "null" ]; then
  echo "  WARNING: Cloudflare credentials not found in Bitwarden (item: cloudflare-dns)."
  echo "  Skipping DNS update. Update your A record manually."
else
  VPS_IP=$(curl -s https://ifconfig.me)
  echo "  VPS public IP: $VPS_IP"

  read -rp "  Enter DNS record name to update (e.g. vps.example.com): " CF_RECORD_NAME

  if [ -z "$CF_RECORD_NAME" ]; then
    echo "  No record name provided. Skipping DNS update."
  else
  echo "  Updating record: $CF_RECORD_NAME"

  # Look up existing DNS record
  CF_RECORD=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=$CF_RECORD_NAME&type=A" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json")

  CF_RECORD_ID=$(echo "$CF_RECORD" | jq -r '.result[0].id // empty')

  if [ -n "$CF_RECORD_ID" ]; then
    # Update existing record
    curl -s -X PUT \
      "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$CF_RECORD_ID" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$CF_RECORD_NAME\",\"content\":\"$VPS_IP\",\"ttl\":300,\"proxied\":false}" \
      | jq -r 'if .success then "  DNS record updated." else "  ERROR: " + (.errors[0].message // "unknown error") end'
  else
    # Create new record
    curl -s -X POST \
      "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"$CF_RECORD_NAME\",\"content\":\"$VPS_IP\",\"ttl\":300,\"proxied\":false}" \
      | jq -r 'if .success then "  DNS record created." else "  ERROR: " + (.errors[0].message // "unknown error") end'
  fi

  fi

  unset CF_API_TOKEN CF_ZONE_ID CF_RECORD_NAME CF_RECORD CF_RECORD_ID VPS_IP
fi

# Remove passwordless sudo (no longer needed after provisioning)
rm -f "/etc/sudoers.d/$USERNAME"

# Clear sensitive variables
unset TOTP_SECRET SSH_PUBLIC_KEY BW_SESSION

echo ""
echo "========================================"
echo "  VPS Provisioning complete!"
echo "========================================"
echo ""
echo "IMPORTANT — remaining steps:"
echo "  1. Add the TOTP secret to your authenticator app (shown above)"
echo "  2. Test SSH:  ssh $USERNAME@<your-ip> -p $SSH_PORT"
echo "  3. Deploy a Laravel project to ~/docker/ and run: docker compose up -d"
echo ""
