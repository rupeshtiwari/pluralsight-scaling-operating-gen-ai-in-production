#!/usr/bin/env bash
# =============================================================================
# Ensure the local environment is READY to run a demo.
#
#   - Docker installed + daemon running (AUTO-STARTS Docker Desktop on macOS if
#     it is installed but not open, and waits until it is ready)
#   - docker compose, tmux, jq, python3, psql, curl present
#   - demo ports (8000 / 5432 / 6379) not already taken by a stale stack
#
# Anything it can auto-fix, it fixes. Anything it can't, it prints the exact
# command to fix. Exits 0 when ready, non-zero otherwise. Called automatically
# by every module's demo_up.sh — you can also run it on its own:
#
#   bash scripts/ensure-ready.sh
# =============================================================================
set -uo pipefail

PINK=$'\033[38;2;255;22;117m'; LIME=$'\033[38;2;207;255;110m'
LGRN=$'\033[38;2;64;255;191m'; BLUE=$'\033[38;2;42;236;250m'
GRAY=$'\033[38;2;191;191;191m'; WHITE=$'\033[1;37m'; R=$'\033[0m'

FAIL=0
ok()   { echo "  ${LIME}✔${R} $1"; }
warn() { echo "  ${BLUE}➜${R} $1"; }
bad()  { echo "  ${PINK}✗${R} $1"; FAIL=1; }
fix()  { echo "     ${GRAY}fix:${R} ${LGRN}$1${R}"; }

echo "${WHITE}Checking the demo environment is ready ...${R}"
IS_MAC=0; [ "$(uname -s)" = "Darwin" ] && IS_MAC=1

# --- Docker + daemon (auto-start on macOS) -----------------------------------
if ! command -v docker >/dev/null 2>&1; then
  bad "Docker is not installed"
  fix "install Docker Desktop for macOS, then re-run"
elif docker info >/dev/null 2>&1; then
  ok "Docker daemon is running"
else
  if [ "$IS_MAC" = "1" ]; then
    warn "Docker daemon not running — starting Docker Desktop (this can take ~30s) ..."
    open -a Docker >/dev/null 2>&1 || open -a "Docker Desktop" >/dev/null 2>&1 || true
    for _ in $(seq 1 45); do
      docker info >/dev/null 2>&1 && break
      printf "."; sleep 2
    done
    echo
    if docker info >/dev/null 2>&1; then
      ok "Docker Desktop started and the daemon is up"
    else
      bad "Docker Desktop did not become ready in time"
      fix "open Docker Desktop manually, wait for the whale icon to settle, then re-run"
    fi
  else
    bad "Docker daemon not running"
    fix "start the Docker daemon, then re-run"
  fi
fi

# --- docker compose ----------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    ok "docker compose is available"
  else
    bad "docker compose plugin missing"
    fix "update Docker Desktop for macOS to 4.44.3 or later"
  fi
fi

# --- CLI tools ---------------------------------------------------------------
for tool in tmux jq python3 psql curl; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool present"
  else
    bad "$tool not found"
    case "$tool" in
      psql) fix "brew install libpq && brew link --force libpq" ;;
      python3) fix "brew install python@3.13" ;;
      *) fix "brew install $tool" ;;
    esac
  fi
done

# --- demo ports free? (a stale stack may be holding them) --------------------
port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
BUSY=""
for p in 8000 5432 6379; do
  if command -v lsof >/dev/null 2>&1 && port_busy "$p"; then BUSY="$BUSY $p"; fi
done
if [ -n "$BUSY" ]; then
  warn "ports in use:${BUSY} — a stack may already be running"
  fix "if a previous demo is still up, stop it: bash module1/scripts/demo_down.sh"
else
  ok "demo ports 8000 / 5432 / 6379 are free"
fi

# --- verdict -----------------------------------------------------------------
echo
if [ "$FAIL" = "0" ]; then
  echo "  ${LIME}READY${R} — the environment is good to go."
  exit 0
else
  echo "  ${PINK}NOT READY${R} — fix the ${PINK}✗${R} items above, then re-run."
  exit 1
fi
