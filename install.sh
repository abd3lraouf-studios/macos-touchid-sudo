#!/bin/bash
# Installer for touchid-sudo.
#
#   curl -fsSL https://raw.githubusercontent.com/abd3lraouf-studios/macos-touchid-sudo/main/install.sh | bash
#
# Detects the machine it is running on: refuses non-macOS and pre-Sonoma
# systems, picks a writable install prefix, offers pam-reattach when tmux is
# present, and offers to run the setup for you.
#
# Environment:
#   PREFIX=/usr/local/bin        where to install the command
#   TOUCHID_SUDO_REF=main        git ref (branch or tag) to install from
#   TOUCHID_SUDO_AUTORUN=1       run the setup afterwards without asking
#   TOUCHID_SUDO_NO_PROMPT=1     never prompt; install the command only
set -euo pipefail

REPO=${TOUCHID_SUDO_REPO:-abd3lraouf-studios/macos-touchid-sudo}
REF=${TOUCHID_SUDO_REF:-main}
SRC="https://raw.githubusercontent.com/$REPO/$REF/bin/touchid-sudo"
AUTORUN=${TOUCHID_SUDO_AUTORUN:-0}
NO_PROMPT=${TOUCHID_SUDO_NO_PROMPT:-0}

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# When piped from curl, stdin is the script itself — prompt on the terminal.
if [[ -r /dev/tty && $NO_PROMPT -eq 0 ]]; then
  ask() { local reply; read -r -p "$1 [y/N] " reply < /dev/tty; [[ $reply == [Yy]* ]]; }
else
  ask() { return 1; }
fi

# --- preflight --------------------------------------------------------------
[[ $(uname -s) == Darwin ]] || die "macOS only"

grep -qE '^[[:space:]]*auth[[:space:]]+include[[:space:]]+sudo_local' /etc/pam.d/sudo 2>/dev/null \
  || die "this Mac's /etc/pam.d/sudo has no sudo_local include — macOS 14 (Sonoma) or later is required"

[[ -e /usr/lib/pam/pam_tid.so.2 || -e /usr/lib/pam/pam_tid.so ]] \
  || die "pam_tid.so not found — this Mac does not support Touch ID"

command -v curl >/dev/null 2>&1 || die "curl is required"

# --- pick an install prefix -------------------------------------------------
# Prefer an explicit PREFIX, then the usual local bin, then a user-owned dir
# that needs no sudo at all.
if [[ -n ${PREFIX:-} ]]; then
  DEST=$PREFIX
elif [[ -d /usr/local/bin ]]; then
  DEST=/usr/local/bin
elif [[ -d /opt/homebrew/bin ]]; then
  DEST=/opt/homebrew/bin
else
  DEST="$HOME/.local/bin"
fi
mkdir -p "$DEST" 2>/dev/null || true
[[ -d $DEST ]] || die "install directory $DEST does not exist and could not be created"

# --- download and verify ----------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

info "Downloading touchid-sudo from $REPO@$REF..."
curl -fsSL "$SRC" -o "$TMP/touchid-sudo" || die "download failed: $SRC"
chmod +x "$TMP/touchid-sudo"

# Sanity-check what we downloaded before putting it on the PATH: a captive
# portal or 404 page must not end up installed as an executable.
head -n1 "$TMP/touchid-sudo" | grep -q '^#!/bin/bash' \
  || die "downloaded file is not the expected script"
VERSION=$("$TMP/touchid-sudo" --version 2>/dev/null) || die "downloaded script failed to run"

# --- install ----------------------------------------------------------------
if [[ -w $DEST ]]; then
  install -m 755 "$TMP/touchid-sudo" "$DEST/touchid-sudo"
else
  info "Installing to $DEST requires sudo."
  sudo install -m 755 "$TMP/touchid-sudo" "$DEST/touchid-sudo"
fi
info "Installed $VERSION to $DEST/touchid-sudo"

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) warn "$DEST is not on your PATH — add it, or run $DEST/touchid-sudo directly" ;;
esac

# --- pam_reattach, only when it would actually matter ------------------------
have_reattach() {
  [[ -f /opt/homebrew/lib/pam/pam_reattach.so ]] \
    || [[ -f /usr/local/lib/pam/pam_reattach.so ]] \
    || [[ -f /opt/local/lib/pam/pam_reattach.so ]]
}

if command -v tmux >/dev/null 2>&1 && ! have_reattach; then
  echo
  info "tmux is installed. Without pam_reattach, Touch ID will not work inside tmux."
  if command -v brew >/dev/null 2>&1; then
    if [[ $AUTORUN -eq 1 ]] || ask "Install pam-reattach via Homebrew now?"; then
      brew install pam-reattach || warn "pam-reattach install failed; continuing without tmux support"
    fi
  else
    info "  Homebrew not found. Install it, then: brew install pam-reattach"
  fi
fi

# --- run the setup ----------------------------------------------------------
echo
if [[ $AUTORUN -eq 1 ]] || ask "Enable Touch ID for sudo now? (requires your password once)"; then
  sudo "$DEST/touchid-sudo"
else
  info "To enable Touch ID for sudo, run:"
  info "  sudo touchid-sudo"
  info "Other commands:  touchid-sudo --status | sudo touchid-sudo --disable"
fi
