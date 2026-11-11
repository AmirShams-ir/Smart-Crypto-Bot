#!/usr/bin/env bash
# Smart Crypto Bot - install/update Freqtrade in an isolated project venv.
# Usage: bash freqtrade.sh [--dir PATH] [--branch stable|develop] [--with-hyperopt] [--no-ta-lib]
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${FREQTRADE_DIR:-$SCRIPT_DIR/freqtrade}"
BRANCH="${FREQTRADE_BRANCH:-stable}"
WITH_HYPEROPT=false
INSTALL_TALIB=true
REPO_URL="${FREQTRADE_REPO_URL:-https://github.com/freqtrade/freqtrade.git}"

info(){ printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m[ OK ]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }
has(){ command -v "$1" >/dev/null 2>&1; }

while (($#)); do
  case "$1" in
    --dir) (($# >= 2)) || die "--dir requires a path"; APP_DIR="$2"; shift 2 ;;
    --branch) (($# >= 2)) || die "--branch requires stable or develop"; BRANCH="$2"; shift 2 ;;
    --with-hyperopt) WITH_HYPEROPT=true; shift ;;
    --no-ta-lib) INSTALL_TALIB=false; shift ;;
    -h|--help)
      cat <<'HELP'
Usage: bash freqtrade.sh [options]
  --dir PATH          Freqtrade checkout path (default: common-modules/freqtrade)
  --branch NAME       Git branch (default: stable)
  --with-hyperopt     Install Hyperopt optional dependencies after base install
  --no-ta-lib         Skip TA-Lib setup (not recommended; some strategies need it)
Environment:
  FREQTRADE_REPO_URL  Git remote URL override
  PYTHON_BIN          Python interpreter to use
  VENV_DIR            Virtualenv path override
HELP
      exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ "$BRANCH" == stable || "$BRANCH" == develop ]] || die "Only stable and develop branches are accepted."
for cmd in git; do has "$cmd" || die "$cmd is required. Run bootstrap.sh first."; done
PYTHON_SCRIPT="$SCRIPT_DIR/python.sh"
[[ -x "$PYTHON_SCRIPT" ]] || die "Missing executable: $PYTHON_SCRIPT (chmod +x python.sh)"
APP_DIR="$(mkdir -p "$(dirname "$APP_DIR")" && cd "$(dirname "$APP_DIR")" && pwd)/$(basename "$APP_DIR")"
VENV_DIR="${VENV_DIR:-$APP_DIR/.venv}"

# Prepare the OS-level build dependencies only when explicitly requested by the caller.
if [[ "${INSTALL_PYTHON_SYSTEM_DEPS:-0}" == 1 ]]; then
  bash "$PYTHON_SCRIPT" --system
fi
PYTHON_ARGS=(--venv "$VENV_DIR")
[[ -z "${PYTHON_VERSION:-}" ]] || PYTHON_ARGS+=(--python "$PYTHON_VERSION")
bash "$PYTHON_SCRIPT" "${PYTHON_ARGS[@]}"

if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" fetch --tags origin
  CURRENT_BRANCH="$(git -C "$APP_DIR" branch --show-current)"
  [[ "$CURRENT_BRANCH" == "$BRANCH" ]] || die "Existing checkout is on '$CURRENT_BRANCH', requested '$BRANCH'. Switch it explicitly before rerunning."
  git -C "$APP_DIR" pull --ff-only origin "$BRANCH"
elif [[ -e "$APP_DIR" ]]; then
  die "$APP_DIR exists but is not a Git checkout."
else
  git clone --filter=blob:none --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
fi

[[ -f "$APP_DIR/setup.sh" && -f "$APP_DIR/pyproject.toml" ]] || die "Freqtrade checkout is incomplete or repository layout changed."
if $INSTALL_TALIB; then
  if [[ -x "$APP_DIR/build_helpers/install_ta-lib.sh" ]]; then
    info "Installing TA-Lib using the helper shipped with the checked-out Freqtrade version."
    (cd "$APP_DIR" && bash build_helpers/install_ta-lib.sh)
  else
    warn "Freqtrade TA-Lib helper not found; the setup installer will decide whether its dependency is already provided."
  fi
fi

info "Installing Freqtrade and its required dependencies..."
(cd "$APP_DIR" && bash setup.sh -i)
[[ -x "$VENV_DIR/bin/freqtrade" ]] || die "Freqtrade executable missing from $VENV_DIR/bin."
"$VENV_DIR/bin/freqtrade" --version
"$VENV_DIR/bin/freqtrade" list-strategies >/dev/null
ok "Freqtrade installation and CLI verification completed."

if $WITH_HYPEROPT; then
  bash "$SCRIPT_DIR/hyperopt.sh" --dir "$APP_DIR"
fi

info "Project directory: $APP_DIR"
info "Virtualenv       : $VENV_DIR"
info "Verify           : $VENV_DIR/bin/freqtrade --version"
