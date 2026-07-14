#!/usr/bin/env bash
# =============================================================================
# Scaling & Operating Gen AI in Production — ONE environment installer.
#
# Run this first. It checks every dependency the demos need, installs anything
# missing (Homebrew on macOS), pins versions, builds the Python venv, and
# writes a full verbose log to environment-setup/setup_log.txt. When it finishes green,
# your Mac is ready to run any module demo step by step.
#
#   bash environment-setup/setup.sh
# =============================================================================
set -uo pipefail

# --- Pluralsight palette ------------------------------------------------------
PINK=$'\033[38;2;255;22;117m'; LIME=$'\033[38;2;207;255;110m'
LGRN=$'\033[38;2;64;255;191m'; BLUE=$'\033[38;2;42;236;250m'
GRAY=$'\033[38;2;191;191;191m'; WHITE=$'\033[1;37m'; R=$'\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/environment-setup/setup_log.txt"
: > "$LOG"

FAILED=0

log()  { echo -e "$*" | tee -a "$LOG"; }
plain(){ echo "$*" >> "$LOG"; }

hdr() {
  log ""
  log "${WHITE}┌──────────────────────────────────────────────────────────────────┐${R}"
  log "${WHITE}│ $1${R}"
  log "${WHITE}└──────────────────────────────────────────────────────────────────┘${R}"
}

ok()   { log "  ${LIME}✔ PASS${R}  $1"; }
warn() { log "  ${BLUE}➜ INFO${R}  $1"; }
bad()  { log "  ${PINK}✗ FAIL${R}  $1"; FAILED=1; }
fix()  { log "         ${GRAY}fix:${R} $1"; }

# --- What this installs --------------------------------------------------------
# One command installs every piece of software the course demos use:
#   Homebrew · Docker Desktop (+ Compose) · tmux · jq · curl · Python 3.13 ·
#   psql (libpq) · the Python virtual environment with pinned dependencies.
# On macOS everything is auto-installed via Homebrew. On other platforms the
# script installs what it can and prints the exact command for anything it
# can't.

# --- Platform -----------------------------------------------------------------
OS="$(uname -s)"
hdr "Platform"
log "  ${BLUE}os:${R} ${LGRN}${OS}${R}"
IS_MAC=0; [ "$OS" = "Darwin" ] && IS_MAC=1

brew_install() {
  local pkg="$1"
  if [ "$IS_MAC" = "1" ] && command -v brew >/dev/null 2>&1; then
    warn "installing ${pkg} via Homebrew ..."
    brew install "$pkg" >>"$LOG" 2>&1 && ok "${pkg} installed" || bad "${pkg} install failed"
  else
    bad "${pkg} missing and cannot auto-install on this platform"
    fix "install ${pkg} with your OS package manager, then re-run this script"
  fi
}

# --- Homebrew -----------------------------------------------------------------
hdr "Homebrew (macOS package manager)"
if command -v brew >/dev/null 2>&1; then
  ok "brew present — $(brew --version | head -1)"
elif [ "$IS_MAC" = "1" ]; then
  warn "Homebrew not found — installing it now (you may be prompted for your Mac password) ..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >>"$LOG" 2>&1 || true
  # Put brew on PATH for the rest of this run (Apple Silicon then Intel).
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
  done
  if command -v brew >/dev/null 2>&1; then
    ok "Homebrew installed — $(brew --version | head -1)"
  else
    bad "Homebrew install did not complete"
    fix "run it manually, then re-run this script: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  fi
else
  warn "not macOS — skipping Homebrew (install tools with your package manager)"
fi

# --- Core CLI tools -----------------------------------------------------------
check_tool() { # name  version-cmd  brew-pkg
  local name="$1" vcmd="$2" pkg="$3"
  if command -v "$name" >/dev/null 2>&1; then
    ok "${name} present — $(eval "$vcmd" 2>&1 | head -1)"
  else
    bad "${name} not found"
    brew_install "$pkg"
  fi
}

hdr "Core tools (tmux, jq, curl, k6)"
check_tool tmux "tmux -V" tmux
check_tool jq   "jq --version" jq
check_tool curl "curl --version" curl
# k6 drives the Module 2 · Clip 2 load spike (also available via Docker Compose).
check_tool k6   "k6 version" k6

# --- Python 3.13 --------------------------------------------------------------
hdr "Python 3.13"
PYBIN=""
for cand in python3.13 python3; do
  if command -v "$cand" >/dev/null 2>&1; then
    ver="$($cand -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)"
    if [ "$ver" = "3.13" ]; then PYBIN="$cand"; break; fi
    [ -z "$PYBIN" ] && PYBIN="$cand" && PYVER="$ver"
  fi
done
if [ -n "$PYBIN" ] && [ "$("$PYBIN" -c 'import sys;print("%d.%d"%sys.version_info[:2])')" = "3.13" ]; then
  ok "python 3.13 present — $($PYBIN --version)"
elif [ -n "$PYBIN" ]; then
  warn "found $($PYBIN --version) — 3.13 is the recording baseline"
  [ "$IS_MAC" = "1" ] && brew_install python@3.13
else
  bad "no python found"; brew_install python@3.13
fi
[ -z "$PYBIN" ] && PYBIN="python3"

# --- psql (PostgreSQL client) -------------------------------------------------
# Used by the host-psql fallback and the readiness check. The demo's Step-5/6
# receipt query runs psql inside the container, so this is belt-and-suspenders.
hdr "PostgreSQL client (psql)"
if command -v psql >/dev/null 2>&1; then
  ok "psql present — $(psql --version)"
elif [ "$IS_MAC" = "1" ] && command -v brew >/dev/null 2>&1; then
  warn "installing psql (libpq) via Homebrew ..."
  if brew install libpq >>"$LOG" 2>&1 && brew link --force libpq >>"$LOG" 2>&1; then
    ok "psql installed (libpq)"
  else
    bad "psql install failed"
    fix "brew install libpq && brew link --force libpq"
  fi
else
  bad "psql not found"
  fix "install the PostgreSQL client (libpq) with your package manager"
fi

# --- Docker Desktop -----------------------------------------------------------
hdr "Docker Desktop + Compose"
if ! command -v docker >/dev/null 2>&1 && [ "$IS_MAC" = "1" ] && command -v brew >/dev/null 2>&1; then
  warn "Docker not found — installing Docker Desktop via Homebrew (large download, be patient) ..."
  brew install --cask docker >>"$LOG" 2>&1 && ok "Docker Desktop installed" || bad "Docker Desktop install failed"
fi
if command -v docker >/dev/null 2>&1; then
  ok "docker present — $(docker --version)"
  if docker compose version >/dev/null 2>&1; then
    ok "docker compose present — $(docker compose version | head -1)"
  else
    bad "docker compose plugin missing"
    fix "update Docker Desktop for macOS to 4.44.3 or later"
  fi
  if docker ps >/dev/null 2>&1; then
    ok "docker daemon is running"
  elif [ "$IS_MAC" = "1" ]; then
    warn "docker daemon not running — starting Docker Desktop (this can take ~30s) ..."
    open -a Docker >/dev/null 2>&1 || open -a "Docker Desktop" >/dev/null 2>&1 || true
    for _ in $(seq 1 45); do docker info >/dev/null 2>&1 && break; printf "."; sleep 2; done; echo
    if docker ps >/dev/null 2>&1; then
      ok "Docker Desktop started and the daemon is up"
    else
      bad "Docker daemon did not become ready in time"
      fix "open Docker Desktop, wait for the whale icon to settle, then re-run"
    fi
  else
    bad "docker daemon not running"
    fix "start the Docker daemon, then re-run"
  fi
else
  bad "docker not found"
  fix "install Docker Desktop for macOS 4.44.3+ from https://www.docker.com/products/docker-desktop/"
fi

# --- Python venv + pinned deps ------------------------------------------------
# Self-healing: we never rely on a bare `pip` on PATH (a reused venv can be
# missing it entirely). We call the venv's own python with `-m pip`, bootstrap
# pip via ensurepip if absent, and rebuild the venv once if the install fails.
hdr "Python virtual environment + pinned dependencies"
VENV="$ROOT/.venv"
VENV_PY="$VENV/bin/python"

make_venv() { "$PYBIN" -m venv "$VENV" >>"$LOG" 2>&1; }

# Install pinned deps into the venv. Returns non-zero on failure.
install_deps() {
  # Bootstrap pip if the venv doesn't have it (the pip: command not found case).
  if ! "$VENV_PY" -m pip --version >>"$LOG" 2>&1; then
    warn "pip missing in venv — bootstrapping with ensurepip ..."
    "$VENV_PY" -m ensurepip --upgrade >>"$LOG" 2>&1 || true
  fi
  "$VENV_PY" -m pip install --upgrade pip setuptools wheel >>"$LOG" 2>&1
  "$VENV_PY" -m pip install -r "$ROOT/requirements.txt" >>"$LOG" 2>&1
}

if [ ! -x "$VENV_PY" ]; then
  warn "creating venv at .venv ..."
  make_venv && ok "venv created" || bad "venv creation failed"
else
  ok "venv already present at .venv"
fi

if [ -x "$VENV_PY" ]; then
  warn "installing pinned requirements (this can take a minute) ..."
  if install_deps; then
    ok "requirements installed"
  else
    # A reused venv can be half-built or missing pip — rebuild once and retry.
    warn "install failed in the existing venv — rebuilding .venv and retrying ..."
    rm -rf "$VENV"
    if make_venv && install_deps; then
      ok "requirements installed (after venv rebuild)"
    else
      bad "requirements install failed — see $LOG"
      fix "rm -rf .venv && bash environment-setup/setup.sh"
    fi
  fi
  if "$VENV_PY" -m pip show fastapi >/dev/null 2>&1; then
    plain "$("$VENV_PY" -m pip freeze)"
    warn "installed versions:"
    for pkg in fastapi uvicorn redis psycopg prometheus-client pytest; do
      v="$("$VENV_PY" -m pip show "$pkg" 2>/dev/null | awk '/^Version:/{print $2}')"
      [ -n "$v" ] && log "  ${BLUE}${pkg}:${R} ${LGRN}${v}${R}"
    done
  fi
fi

# --- Verdict ------------------------------------------------------------------
hdr "Environment verdict"
if [ "$FAILED" = "0" ]; then
  log "  ${LIME}READY${R} — every dependency is installed and pinned."
  log "  ${GRAY}next:${R} start a module demo, e.g. ${LGRN}bash module1/scripts/demo_up.sh${R}"
else
  log "  ${PINK}NOT READY${R} — fix the ${PINK}FAIL${R} lines above, then re-run:"
  log "         ${LGRN}bash environment-setup/setup.sh${R}"
fi
log ""
log "  ${GRAY}full log written to:${R} ${LGRN}environment-setup/setup_log.txt${R}"
exit "$FAILED"
