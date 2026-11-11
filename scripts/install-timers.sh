#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Install Market Adviser systemd timer templates for the current project user.
# The project directory is detected from this script's real location.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

info(){ printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m[ OK ]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# Resolve symlinks so systemd always receives an absolute, stable path.
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" = /* ]] || SOURCE="$DIR/$SOURCE"
done
APP_DIR="$(cd -P "$(dirname "$SOURCE")/.." >/dev/null 2>&1 && pwd)"
SYSTEMD_SOURCE_DIR="$APP_DIR/systemd"
SYSTEMD_TARGET_DIR="/etc/systemd/system"

[[ -f "$APP_DIR/install.sh" && -f "$APP_DIR/requirements.txt" ]] ||
  die "Could not identify a Market Adviser project directory at: $APP_DIR"
[[ -f "$SYSTEMD_SOURCE_DIR/market-advisor-fetch@.service" ]] ||
  die "Missing service template: $SYSTEMD_SOURCE_DIR/market-advisor-fetch@.service"
[[ -x "$APP_DIR/.venv/bin/python" ]] ||
  die "Python virtual environment not found. Run ./install.sh first."
[[ -f "$APP_DIR/.env" ]] ||
  die ".env not found. Run ./install.sh and configure TWELVE_API_KEY first."

if [[ "$EUID" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "sudo is required. Run: sudo bash scripts/install-timers.sh"
  exec sudo --preserve-env=PATH bash "$SOURCE" "$@"
fi

# Use the owner of the project directory, not the invoking/root user.
APP_USER="$(stat -c '%U' "$APP_DIR")"
APP_GROUP="$(stat -c '%G' "$APP_DIR")"
[[ -n "$APP_USER" && "$APP_USER" != "UNKNOWN" ]] || die "Cannot detect project owner."
[[ "$APP_USER" != "root" ]] || die "Project is owned by root. Run install.sh as a normal user and keep the project user-owned."
id "$APP_USER" >/dev/null 2>&1 || die "Project owner account does not exist: $APP_USER"

# systemd unit values must be safely representable in unit files.
[[ "$APP_DIR" != *$'\n'* && "$APP_DIR" != *$'\r'* ]] || die "Project path contains a newline."
[[ "$APP_USER" =~ ^[a-z_][a-z0-9_-]*\$?$ ]] || die "Unsupported project username for systemd: $APP_USER"

install -d -m 0755 "$SYSTEMD_TARGET_DIR"
TMP_DIR="$(mktemp -d)"
cleanup(){ rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Generate the service with the detected path and owner. The EnvironmentFile
# is optional at service start so a missing local file gets a clear app error,
# while this installer still requires it before enabling timers.
sed \
  -e "s|@APP_USER@|$APP_USER|g" \
  -e "s|@APP_DIR@|$APP_DIR|g" \
  "$SYSTEMD_SOURCE_DIR/market-advisor-fetch@.service" \
  > "$TMP_DIR/market-advisor-fetch@.service"

for unit in \
  market-advisor-fetch@.service \
  market-advisor-1h@.timer \
  market-advisor-4h@.timer \
  market-advisor-1day@.timer \
  market-advisor-1week@.timer; do
  [[ -s "$TMP_DIR/$unit" ]] || cp "$SYSTEMD_SOURCE_DIR/$unit" "$TMP_DIR/$unit"
done

# Validate templates before installing.
grep -Fq "User=$APP_USER" "$TMP_DIR/market-advisor-fetch@.service" ||
  die "Generated service has an incorrect User directive."
grep -Fq "WorkingDirectory=$APP_DIR" "$TMP_DIR/market-advisor-fetch@.service" ||
  die "Generated service has an incorrect WorkingDirectory directive."
grep -Fq "$APP_DIR/.venv/bin/python" "$TMP_DIR/market-advisor-fetch@.service" ||
  die "Generated service does not point to the project virtualenv."

for unit in "$TMP_DIR"/*; do
  install -o root -g root -m 0644 "$unit" "$SYSTEMD_TARGET_DIR/$(basename "$unit")"
done

systemctl daemon-reload
systemd-analyze verify \
  "$SYSTEMD_TARGET_DIR/market-advisor-fetch@.service" \
  "$SYSTEMD_TARGET_DIR/market-advisor-1h@.timer" \
  "$SYSTEMD_TARGET_DIR/market-advisor-4h@.timer" \
  "$SYSTEMD_TARGET_DIR/market-advisor-1day@.timer" \
  "$SYSTEMD_TARGET_DIR/market-advisor-1week@.timer" ||
  die "systemd unit verification failed. Units were installed but no timers were enabled."

ok "Market Adviser systemd units installed."
info "Project directory : $APP_DIR"
info "Run as user       : $APP_USER"
info "Primary group     : $APP_GROUP"
info "Python            : $APP_DIR/.venv/bin/python"
info "Environment       : $APP_DIR/.env"
printf '\n'
info "Enable timers for BTC_USD with:"
printf '  sudo systemctl enable --now market-advisor-1h@BTC_USD.timer\n'
printf '  sudo systemctl enable --now market-advisor-4h@BTC_USD.timer\n'
printf '  sudo systemctl enable --now market-advisor-1day@BTC_USD.timer\n'
printf '  sudo systemctl enable --now market-advisor-1week@BTC_USD.timer\n'
printf '\n'
info "Inspect with: systemctl list-timers 'market-advisor-*'"
