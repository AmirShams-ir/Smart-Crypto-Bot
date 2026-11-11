#!/usr/bin/env bash
# Smart Crypto Bot - Python runtime and virtual environment provisioning.
# Usage: bash python.sh [--venv PATH] [--python VERSION] [--system]
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_VERSION="${PYTHON_VERSION:-}"
VENV_DIR="${VENV_DIR:-$SCRIPT_DIR/.venv}"
INSTALL_SYSTEM=false
LOG_FILE="${PYTHON_INSTALL_LOG:-}"

info(){ printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m[ OK ]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
has(){ command -v "$1" >/dev/null 2>&1; }

while (($#)); do
  case "$1" in
    --venv) (($# >= 2)) || die "--venv requires a path"; VENV_DIR="$2"; shift 2 ;;
    --python) (($# >= 2)) || die "--python requires a version (for example 3.12)"; PYTHON_VERSION="$2"; shift 2 ;;
    --system) INSTALL_SYSTEM=true; shift ;;
    -h|--help)
      cat <<'HELP'
Usage: bash python.sh [options]
  --venv PATH       Virtual environment location (default: common-modules/.venv)
  --python VERSION  Require a specific Python minor version (e.g. 3.12)
  --system          Install system Python/build packages (requires sudo)
HELP
      exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

if $INSTALL_SYSTEM; then
  ((EUID == 0)) || { has sudo || die "sudo is required"; exec sudo --preserve-env=PATH bash "$0" "$@"; }
  [[ -r /etc/os-release ]] || die "Unsupported OS: /etc/os-release not found"
  . /etc/os-release
  case "${ID:-}" in debian|ubuntu|armbian) ;; *) die "Only Debian/Ubuntu-family systems are supported" ;; esac
  apt-get update
  apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv python3-dev \
    build-essential pkg-config cmake ninja-build \
    libffi-dev libssl-dev libbz2-dev liblzma-dev \
    libreadline-dev libsqlite3-dev zlib1g-dev \
    libncurses-dev libgdbm-dev libnss3-dev ca-certificates git curl
fi

PYTHON_BIN=""
if [[ -n "$PYTHON_VERSION" ]]; then
  for candidate in "python$PYTHON_VERSION" "python${PYTHON_VERSION/./}"; do
    if command -v "$candidate" >/dev/null 2>&1; then PYTHON_BIN="$(command -v "$candidate")"; break; fi
  done
else
  for candidate in python3.13 python3.12 python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then PYTHON_BIN="$(command -v "$candidate")"; break; fi
  done
fi
[[ -n "$PYTHON_BIN" ]] || die "Python ${PYTHON_VERSION:-3} not found. Run with --system or install Python first."

PY_VERSION="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ -n "$PYTHON_VERSION" && "$PY_VERSION" != "$PYTHON_VERSION" ]]; then
  die "Requested Python $PYTHON_VERSION, found $PY_VERSION."
fi
"$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' ||
  die "Python 3.11+ is required for the current Freqtrade release; found $PY_VERSION."

VENV_DIR="$(mkdir -p "$(dirname "$VENV_DIR")" && cd "$(dirname "$VENV_DIR")" && pwd)/$(basename "$VENV_DIR")"
if [[ -x "$VENV_DIR/bin/python" ]]; then
  EXISTING="$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  [[ "$EXISTING" == "$PY_VERSION" ]] || die "Existing venv uses Python $EXISTING, selected Python is $PY_VERSION. Choose another --venv path."
  info "Reusing existing virtual environment: $VENV_DIR"
else
  [[ ! -e "$VENV_DIR" ]] || die "$VENV_DIR exists but is not a valid venv; move it aside before retrying."
  "$PYTHON_BIN" -m venv "$VENV_DIR" || die "Could not create virtual environment. Install python3-venv."
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
"$VENV_DIR/bin/python" -m pip --version >/dev/null
"$VENV_DIR/bin/python" -c 'import ssl, venv, sqlite3; print("Python runtime checks: OK")'
ok "Python $PY_VERSION ready."
info "Interpreter : $PYTHON_BIN"
info "Virtualenv  : $VENV_DIR"
info "Activate    : source "$VENV_DIR/bin/activate""
