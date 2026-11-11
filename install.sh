#!/usr/bin/env bash
# Smart Crypto Bot - ordered installer and stage-by-stage report.
# Usage: bash install.sh [--with-hyperopt] [--skip-bootstrap] [--skip-upgrade] [--no-firewall]
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${INSTALL_LOG_DIR:-$SCRIPT_DIR/logs/install}"
WITH_HYPEROPT="${INSTALL_HYPEROPT:-0}"
SKIP_BOOTSTRAP=false
SKIP_UPGRADE=false
NO_FIREWALL=false
STARTED_AT="$(date +%s)"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
CURRENT_STAGE="Initialization"
CURRENT_LOG=""
REPORT_FILE=""

info(){ printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m[ OK ]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --with-hyperopt) WITH_HYPEROPT=1; shift ;;
    --skip-bootstrap) SKIP_BOOTSTRAP=true; shift ;;
    --skip-upgrade) SKIP_UPGRADE=true; shift ;;
    --no-firewall) NO_FIREWALL=true; shift ;;
    -h|--help)
      cat <<'HELP'
Usage: bash install.sh [options]
  --with-hyperopt   Install optional Hyperopt dependencies after Freqtrade
  --skip-bootstrap  Skip OS provisioning on an already prepared host
  --skip-upgrade    Pass --skip-upgrade to bootstrap.sh
  --no-firewall     Pass --no-firewall to bootstrap.sh
Environment:
  FREQTRADE_DIR     Freqtrade checkout path (default: common-modules/freqtrade)
  PYTHON_VERSION    Python minor version (e.g. 3.12)
  INSTALL_HYPEROPT  Set to 1 to install Hyperopt by default
  INSTALL_LOG_DIR   Override report/log directory
HELP
      exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# Keep the orchestrator unprivileged; elevate only the OS bootstrap.
(( EUID != 0 )) || die "Run install.sh as a normal project user, not root. sudo is used only for bootstrap."
command -v sudo >/dev/null 2>&1 || die "sudo is required, or use --skip-bootstrap on a prepared host."

mkdir -p "$LOG_DIR"
REPORT_FILE="$LOG_DIR/report-$RUN_ID.txt"
touch "$REPORT_FILE"
exec > >(tee -a "$LOG_DIR/install-$RUN_ID.log") 2>&1

printf 'Smart Crypto Bot installation report\nRun ID: %s\nStarted: %s\n\n' "$RUN_ID" "$(date -Is)" > "$REPORT_FILE"
printf '%-24s | %-10s | %8s | %s\n' "STAGE" "STATUS" "SECONDS" "LOG" | tee -a "$REPORT_FILE"
printf '%s\n' '-------------------------+------------+----------+----------------------------------------' | tee -a "$REPORT_FILE"

report_stage(){
  printf '%-24s | %-10s | %8ss | %s\n' "$1" "$2" "$3" "$4" | tee -a "$REPORT_FILE"
}

run_stage(){
  local name="$1"; shift
  local log_file="$LOG_DIR/${RUN_ID}-${name//[^a-zA-Z0-9_-]/_}.log"
  local start end elapsed rc=0
  CURRENT_STAGE="$name"
  CURRENT_LOG="$log_file"
  start="$(date +%s)"
  info "============================================================"
  info "START: $name"
  info "Log: $log_file"
  set +e
  "$@" 2>&1 | tee "$log_file"
  rc=${PIPESTATUS[0]}
  set -e
  end="$(date +%s)"
  elapsed="$((end-start))"
  if (( rc == 0 )); then
    ok "$name completed in ${elapsed}s"
    report_stage "$name" "PASS" "$elapsed" "$log_file"
  else
    report_stage "$name" "FAIL($rc)" "$elapsed" "$log_file"
    printf '\nINSTALLATION RESULT: FAILED\nRun ID: %s\nFailed stage: %s\nExit code: %s\nStage log: %s\nReport: %s\n' "$RUN_ID" "$name" "$rc" "$log_file" "$REPORT_FILE" | tee -a "$REPORT_FILE"
    die "Installation stopped at stage: $name (exit $rc)."
  fi
}

info "Smart Crypto Bot installer starting."
info "Order: system bootstrap -> Python -> Freqtrade -> optional Hyperopt."

if [[ "$SKIP_BOOTSTRAP" == false ]]; then
  BOOT_ARGS=()
  [[ "$SKIP_UPGRADE" == false ]] || BOOT_ARGS+=(--skip-upgrade)
  [[ "$NO_FIREWALL" == false ]] || BOOT_ARGS+=(--no-firewall)
  run_stage "System bootstrap" sudo bash "$SCRIPT_DIR/bootstrap.sh" "${BOOT_ARGS[@]}"
else
  info "System bootstrap skipped by request."
fi

PY_ARGS=()
[[ -z "${PYTHON_VERSION:-}" ]] || PY_ARGS+=(--python "$PYTHON_VERSION")
run_stage "Python environment" bash "$SCRIPT_DIR/python.sh" "${PY_ARGS[@]}"

FT_ARGS=()
[[ "$WITH_HYPEROPT" != 1 ]] || FT_ARGS+=(--with-hyperopt)
run_stage "Freqtrade installation" bash "$SCRIPT_DIR/freqtrade.sh" "${FT_ARGS[@]}"

if [[ "$WITH_HYPEROPT" == 1 ]]; then
  run_stage "Hyperopt verification" bash "$SCRIPT_DIR/hyperopt.sh"
else
  info "Hyperopt skipped (optional). Use --with-hyperopt to install it."
fi

END_AT="$(date +%s)"
TOTAL="$((END_AT-STARTED_AT))"
{
  printf '\nINSTALLATION RESULT: SUCCESS\n'
  printf 'Run ID          : %s\n' "$RUN_ID"
  printf 'Finished        : %s\n' "$(date -Is)"
  printf 'Total duration  : %ss\n' "$TOTAL"
  printf 'Hyperopt        : %s\n' "$([[ "$WITH_HYPEROPT" == 1 ]] && echo installed || echo skipped)"
  printf 'Freqtrade path  : %s\n' "${FREQTRADE_DIR:-$SCRIPT_DIR/freqtrade}"
  printf 'Virtualenv      : %s\n' "${VENV_DIR:-${FREQTRADE_DIR:-$SCRIPT_DIR/freqtrade}/.venv}"
  printf 'Stage report    : %s\n' "$REPORT_FILE"
} | tee -a "$REPORT_FILE"

ok "All requested installation stages completed."
info "Full log: $LOG_DIR/install-$RUN_ID.log"
info "Report  : $REPORT_FILE"
