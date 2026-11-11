#!/usr/bin/env bash
# Smart Crypto Bot - unified Debian/Ubuntu server bootstrap.
# Supports Debian 12/13, Ubuntu 22.04/24.04 and Debian-based Armbian.
# Run: sudo bash common-modules/bootstrap.sh [--skip-upgrade] [--no-firewall]
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="bootstrap"
LOG_FILE="/var/log/smart-crypto-bot-bootstrap.log"
APT_MAIN="/etc/apt/sources.list"
APT_MIRRORS="/etc/apt/sources.list.d/99-smart-crypto-bot-mirrors.list"
APT_PIN="/etc/apt/preferences.d/99-smart-crypto-bot-mirror-priority"
APT_RETRIES="/etc/apt/apt.conf.d/99-smart-crypto-bot-retries"
SYSCTL_FILE="/etc/sysctl.d/99-smart-crypto-bot.conf"
BBR_FILE="/etc/sysctl.d/99-smart-crypto-bot-bbr.conf"
JOURNAL_FILE="/etc/systemd/journald.conf.d/99-smart-crypto-bot.conf"
ZRAM_FILE="/etc/default/zramswap"
UNATTENDED_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
SKIP_UPGRADE=false
ENABLE_FIREWALL=true
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

for arg in "$@"; do
  case "$arg" in
    --skip-upgrade) SKIP_UPGRADE=true ;;
    --no-firewall) ENABLE_FIREWALL=false ;;
    -h|--help)
      echo "Usage: sudo bash bootstrap.sh [--skip-upgrade] [--no-firewall]"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

info(){ printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m[ OK ]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
has(){ command -v "$1" >/dev/null 2>&1; }
has_systemd(){ [[ -d /run/systemd/system ]] && has systemctl; }
backup_file(){
  local path="$1"
  [[ -e "$path" ]] && cp -a -- "$path" "\${path}.bak.\${TIMESTAMP}"
}
apt_install(){ DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }

if (( EUID != 0 )); then
  if has sudo; then exec sudo --preserve-env=PATH bash "$0" "$@"; fi
  die "Run as root (sudo is not installed)."
fi
[[ -r /etc/os-release ]] || die "/etc/os-release is missing."
# shellcheck disable=SC1091
. /etc/os-release
OS_ID="\${ID:-}"
OS_VERSION="\${VERSION_ID:-}"
OS_CODENAME="\${VERSION_CODENAME:-}"
PRETTY="\${PRETTY_NAME:-unknown}"
IS_ARMBIAN=false
[[ "$OS_ID" == armbian || -f /etc/armbian-release || -n "\${ARMBIAN_PRETTY_NAME:-}" ]] && IS_ARMBIAN=true

case "$OS_ID" in
  debian|armbian)
    case "$OS_VERSION" in
      12|12.*) CODENAME=bookworm; COMPONENTS="main contrib non-free non-free-firmware" ;;
      13|13.*) CODENAME=trixie; COMPONENTS="main contrib non-free non-free-firmware" ;;
      *) die "Unsupported Debian release: $OS_VERSION (supported: 12, 13)." ;;
    esac
    OS_FAMILY=debian
    ;;
  ubuntu)
    case "$OS_VERSION" in
      22.04) CODENAME=jammy ;;
      24.04) CODENAME=noble ;;
      *) die "Unsupported Ubuntu release: $OS_VERSION (supported: 22.04, 24.04)." ;;
    esac
    COMPONENTS="main restricted universe multiverse"
    OS_FAMILY=ubuntu
    ;;
  *)
    die "Unsupported OS: $PRETTY. Debian 12/13 and Ubuntu 22.04/24.04 are supported."
    ;;
esac

mkdir -p /var/log
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
export DEBIAN_FRONTEND=noninteractive

info "============================================================"
info " Smart Crypto Bot - Unified Bootstrap"
info " OS: $PRETTY | Family: $OS_FAMILY | Codename: $CODENAME"
info " Armbian: $IS_ARMBIAN | Started: $(date -Is)"
info "============================================================"

# Hardware and architecture inventory.
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
KERNEL_ARCH="$(uname -m)"
CPU_MODEL="$(awk -F: '/model name|Hardware|Model/ {sub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
CPU_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
RAM_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
RAM_MB="$((RAM_KB / 1024))"
ROOT_TOTAL_MB="$(df -Pm / | awk 'NR==2 {print $2}')"
ROOT_FREE_MB="$(df -Pm / | awk 'NR==2 {print $4}')"
info "Architecture: $ARCH ($KERNEL_ARCH)"
info "CPU: \${CPU_MODEL:-unknown} | Threads: $CPU_THREADS"
info "RAM: \${RAM_MB} MB | Root disk: \${ROOT_TOTAL_MB} MB total, \${ROOT_FREE_MB} MB free"

# Preserve current apt configuration before changing it.
mkdir -p /etc/apt/sources.list.d /etc/apt/preferences.d /etc/apt/apt.conf.d
backup_file "$APT_MAIN"
backup_file "$APT_MIRRORS"
backup_file "$APT_PIN"
backup_file "$APT_RETRIES"

# Prefer official repositories and keep mirrors as lower-priority fallbacks.
if [[ "$OS_FAMILY" == debian ]]; then
  cat >"$APT_MAIN" <<EOF
# Managed by Smart Crypto Bot bootstrap. Official Debian repositories.
deb https://deb.debian.org/debian $CODENAME $COMPONENTS
deb https://deb.debian.org/debian $CODENAME-updates $COMPONENTS
deb https://security.debian.org/debian-security $CODENAME-security $COMPONENTS
EOF
  cat >"$APT_MIRRORS" <<EOF
# Official CDN alternative
deb https://cdn-aws.deb.debian.org/debian $CODENAME $COMPONENTS
deb https://cdn-aws.deb.debian.org/debian $CODENAME-updates $COMPONENTS
deb https://cdn-aws.deb.debian.org/debian-security $CODENAME-security $COMPONENTS
# Community mirrors (fallback only)
deb https://mirror.cdn.ir/repository/debian $CODENAME $COMPONENTS
deb https://mirror.cdn.ir/repository/debian $CODENAME-updates $COMPONENTS
deb https://repo.iut.ac.ir/debian $CODENAME $COMPONENTS
deb https://mirror.arvancloud.ir/debian $CODENAME $COMPONENTS
EOF
  cat >"$APT_PIN" <<'EOF'
Package: *
Pin: origin "deb.debian.org"
Pin-Priority: 1000

Package: *
Pin: origin "security.debian.org"
Pin-Priority: 1000

Package: *
Pin: origin "cdn-aws.deb.debian.org"
Pin-Priority: 900

Package: *
Pin: origin "mirror.cdn.ir"
Pin-Priority: 500

Package: *
Pin: origin "repo.iut.ac.ir"
Pin-Priority: 450

Package: *
Pin: origin "mirror.arvancloud.ir"
Pin-Priority: 400
EOF
  # Never overwrite Armbian's vendor repositories.
  if $IS_ARMBIAN; then
    info "Armbian detected; preserving its vendor repository definitions."
  fi
else
  cat >"$APT_MAIN" <<EOF
# Managed by Smart Crypto Bot bootstrap. Official Ubuntu repositories.
deb https://archive.ubuntu.com/ubuntu $CODENAME $COMPONENTS
deb https://archive.ubuntu.com/ubuntu $CODENAME-updates $COMPONENTS
deb https://archive.ubuntu.com/ubuntu $CODENAME-backports $COMPONENTS
deb https://security.ubuntu.com/ubuntu $CODENAME-security $COMPONENTS
EOF
  cat >"$APT_MIRRORS" <<EOF
# Official Ubuntu archive CDN alternative
deb https://ubuntu-archive.trafficmanager.net/ubuntu $CODENAME $COMPONENTS
deb https://ubuntu-archive.trafficmanager.net/ubuntu $CODENAME-updates $COMPONENTS
deb https://ubuntu-archive.trafficmanager.net/ubuntu $CODENAME-backports $COMPONENTS
# Community mirrors (fallback only)
deb https://mirror.cdn.ir/ubuntu $CODENAME $COMPONENTS
deb https://mirror.cdn.ir/ubuntu $CODENAME-updates $COMPONENTS
deb https://mirror.cdn.ir/ubuntu $CODENAME-security $COMPONENTS
deb https://repo.iut.ac.ir/ubuntu $CODENAME $COMPONENTS
deb https://repo.iut.ac.ir/ubuntu $CODENAME-updates $COMPONENTS
deb https://repo.iut.ac.ir/ubuntu $CODENAME-security $COMPONENTS
deb https://mirror.arvancloud.ir/ubuntu $CODENAME $COMPONENTS
EOF
  cat >"$APT_PIN" <<'EOF'
Package: *
Pin: origin "archive.ubuntu.com"
Pin-Priority: 1000

Package: *
Pin: origin "security.ubuntu.com"
Pin-Priority: 1000

Package: *
Pin: origin "ubuntu-archive.trafficmanager.net"
Pin-Priority: 900

Package: *
Pin: origin "mirror.cdn.ir"
Pin-Priority: 500

Package: *
Pin: origin "repo.iut.ac.ir"
Pin-Priority: 450

Package: *
Pin: origin "mirror.arvancloud.ir"
Pin-Priority: 400
EOF
fi

cat >"$APT_RETRIES" <<'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "20";
Acquire::https::Timeout "20";
Acquire::Queue-Mode "access";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
# IPv4 is preferred for APT only; IPv6 remains enabled system-wide.
cat >/etc/apt/apt.conf.d/99-smart-crypto-bot-ipv4 <<'EOF'
Acquire::ForceIPv4 "true";
EOF
ok "APT official sources, fallback mirrors and retry policy configured."

info "Refreshing package metadata..."
apt-get update || die "APT update failed; verify DNS/network and mirror reachability."
if ! $SKIP_UPGRADE; then
  apt-get upgrade -y || warn "Full upgrade reported errors; continuing with bootstrap packages."
fi

# Base admin, build, security and diagnostic packages.
PACKAGES=(
  ca-certificates apt-transport-https software-properties-common
  sudo git curl wget build-essential pkg-config
  openssh-server lsb-release pciutils usbutils
  systemd-timesyncd zram-tools
  unattended-upgrades apt-listchanges
  fail2ban ufw
  util-linux procps iproute2 iputils-ping
)
apt_install "\${PACKAGES[@]}" || die "Required package installation failed."
ok "Base tools and security packages installed."

# Keep optional Python development support available for application deployments.
if [[ "\${INSTALL_PYTHON_BUILD_DEPS:-0}" == 1 ]]; then
  apt_install python3 python3-pip python3-venv python3-dev libffi-dev libssl-dev
fi

# Time synchronization: do not change the host timezone.
if has_systemd; then
  timedatectl set-ntp true 2>/dev/null || warn "timedatectl could not enable NTP."
  systemctl enable --now systemd-timesyncd.service 2>/dev/null || warn "systemd-timesyncd could not be enabled."
  timedatectl show -p NTPSynchronized --value 2>/dev/null || true
else
  warn "systemd unavailable; automatic NTP service activation skipped."
fi

# ZRAM size follows physical memory. The disk swap is deliberately modest.
if (( RAM_MB <= 1024 )); then ZRAM_PERCENT=100
elif (( RAM_MB <= 2048 )); then ZRAM_PERCENT=75
elif (( RAM_MB <= 4096 )); then ZRAM_PERCENT=50
else ZRAM_PERCENT=25
fi
backup_file "$ZRAM_FILE"
cat >"$ZRAM_FILE" <<EOF
# Managed by Smart Crypto Bot bootstrap
ALGO=zstd
PERCENT=$ZRAM_PERCENT
PRIORITY=100
EOF
if has_systemd && systemctl list-unit-files 2>/dev/null | grep -q '^zramswap.service'; then
  systemctl daemon-reload
  systemctl enable --now zramswap.service || warn "Could not activate zramswap."
else
  warn "zramswap.service unavailable; ZRAM configuration has been written."
fi
if ! swapon --show --noheadings 2>/dev/null | grep -q .; then
  if [[ ! -e /swapfile ]]; then
    if (( RAM_MB <= 1024 )); then SWAP_MB=1024
    elif (( RAM_MB <= 4096 )); then SWAP_MB=1024
    else SWAP_MB=512
    fi
    DISK_FREE_MB="$(df -Pm / | awk 'NR==2 {print $4}')"
    if (( DISK_FREE_MB > SWAP_MB + 1024 )); then
      (fallocate -l "\${SWAP_MB}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB" status=none) \
        && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile \
        && { grep -qE '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab || echo '/swapfile none swap sw,pri=10 0 0' >>/etc/fstab; } \
        && ok "Disk swap enabled (\${SWAP_MB} MB)." || warn "Disk swap creation failed."
    else
      warn "Insufficient free disk space for additional swap; skipped."
    fi
  else
    warn "/swapfile exists but is not active; leaving it untouched."
  fi
else
  ok "Existing swap detected; no disk swap changes made."
fi

# Conservative, broadly compatible kernel/network baseline.
backup_file "$SYSCTL_FILE"
cat >"$SYSCTL_FILE" <<'EOF'
# Managed by Smart Crypto Bot bootstrap.
vm.swappiness=20
vm.vfs_cache_pressure=50
fs.file-max=100000
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
EOF
sysctl --system >/dev/null || warn "Some sysctl settings could not be applied."
modprobe tcp_bbr 2>/dev/null || true
if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
  cat >"$BBR_FILE" <<'EOF'
# Managed by Smart Crypto Bot bootstrap.
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null && ok "TCP BBR enabled."
else
  rm -f "$BBR_FILE"
  warn "TCP BBR is not supported by the running kernel; left disabled."
fi

# Journald retention bounds.
if has_systemd; then
  mkdir -p "$(dirname "$JOURNAL_FILE")"
  backup_file "$JOURNAL_FILE"
  cat >"$JOURNAL_FILE" <<'EOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
MaxRetentionSec=14day
Compress=yes
EOF
  systemctl restart systemd-journald.service || warn "Could not restart journald."
fi

# Fail2ban with a minimal sshd jail. Respect the SSH port configured by sshd.
mkdir -p /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/99-smart-crypto-bot-sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
if has_systemd; then
  systemctl enable --now fail2ban.service || warn "Fail2ban could not be started."
fi

# UFW: allow active SSH port before enabling, to avoid locking out remote admins.
if $ENABLE_FIREWALL; then
  SSH_PORTS=()
  if has sshd; then
    while IFS= read -r port; do
      [[ "$port" =~ ^[0-9]+$ ]] && SSH_PORTS+=("$port")
    done < <(sshd -T 2>/dev/null | awk '$1=="port" {print $2}' | sort -nu || true)
  fi
  (("\${#SSH_PORTS[@]}" > 0)) || SSH_PORTS=(22)
  ufw default deny incoming
  ufw default allow outgoing
  for port in "\${SSH_PORTS[@]}"; do ufw allow "$port/tcp" comment 'SSH access'; done
  ufw --force enable || warn "UFW activation failed."
  if has_systemd; then systemctl enable ufw.service 2>/dev/null || true; fi
else
  info "Firewall activation explicitly skipped (--no-firewall)."
fi

# Security updates: install unattended security updates, but do not auto-reboot.
mkdir -p /etc/apt/apt.conf.d
backup_file "$UNATTENDED_FILE"
cat >"$UNATTENDED_FILE" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
if has_systemd; then
  systemctl enable --now unattended-upgrades.service 2>/dev/null || true
fi
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || warn "Unattended-upgrades reconfiguration skipped."

# Final health and disk checks.
info "Disk capacity:"
df -hT /
info "Memory and swap:"
free -h
swapon --show 2>/dev/null || true
info "Service health:"
for service in systemd-timesyncd fail2ban ufw unattended-upgrades systemd-journald zramswap; do
  if has_systemd && systemctl list-unit-files 2>/dev/null | grep -q "^$service\.service"; then
    if systemctl is-active --quiet "$service.service"; then
      ok "$service.service active"
    else
      warn "$service.service is installed but not active"
    fi
  fi
done
info "APT policy sample:"
apt-cache policy bash | sed -n '1,16p' || true
info "Bootstrap finished: $(date -Is)"
ok "Unified bootstrap completed. Log: $LOG_FILE"
