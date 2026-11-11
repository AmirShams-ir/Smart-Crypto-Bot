#!/usr/bin/env bash
# Smart Crypto Bot - install and verify Freqtrade's optional Hyperopt dependencies.
# Usage: bash hyperopt.sh [--dir PATH] [--check-only]
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${FREQTRADE_DIR:-$SCRIPT_DIR/freqtrade}"
CHECK_ONLY=false

info(){ printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m[ OK ]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --dir) (($# >= 2)) || die "--dir requires a path"; APP_DIR="$2"; shift 2 ;;
    --check-only) CHECK_ONLY=true; shift ;;
    -h|--help)
      cat <<'HELP'
Usage: bash hyperopt.sh [options]
  --dir PATH       Freqtrade checkout path (default: common-modules/freqtrade)
  --check-only     Verify current Hyperopt dependencies without installing
HELP
      exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

APP_DIR="$(cd "$APP_DIR" 2>/dev/null && pwd)" || die "Freqtrade directory not found: $APP_DIR"
VENV_DIR="${VENV_DIR:-$APP_DIR/.venv}"
PYTHON="$VENV_DIR/bin/python"
FREQTRADE="$VENV_DIR/bin/freqtrade"
[[ -x "$PYTHON" && -x "$FREQTRADE" ]] || die "Freqtrade venv missing. Run freqtrade.sh first."
[[ -f "$APP_DIR/requirements-hyperopt.txt" ]] || die "requirements-hyperopt.txt missing; the Freqtrade checkout may be incompatible."

if ! $CHECK_ONLY; then
  info "Installing optional Hyperopt dependencies..."
  "$PYTHON" -m pip install -r "$APP_DIR/requirements-hyperopt.txt"
fi

"$PYTHON" - <<'PY'
import importlib.util
import sys

required = ("optuna", "skopt")
missing = [name for name in required if importlib.util.find_spec(name) is None]
if missing:
    print("Missing Hyperopt modules:", ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
print("Hyperopt Python dependency imports: OK")
PY

"$FREQTRADE" hyperopt --help >/dev/null
ok "Hyperopt dependencies and CLI verified."
info "Run Hyperopt with: $FREQTRADE hyperopt --config user_data/config.json --strategy YOUR_STRATEGY"
info "Hyperopt is CPU/RAM intensive; run optimization on a suitably resourced machine."
