#!/bin/bash
# Test suite for touchid-sudo.
#
# Runs the real script against fixture files in a temp directory using the
# TOUCHID_SUDO_* hooks, so nothing under /etc is touched and no root is needed.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$SCRIPT_DIR/../bin/touchid-sudo"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; printf '      %s\n' "${2:-}"; FAIL=$((FAIL + 1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# A stand-in for /etc/pam.d/sudo that contains the include line the script
# requires, and a stand-in for /etc/pam.d/sudo_local that it manages.
FAKE_PAM_SUDO="$WORK/sudo"
FAKE_TARGET="$WORK/sudo_local"
printf 'auth       include        sudo_local\nauth       required       pam_opendirectory.so\n' > "$FAKE_PAM_SUDO"

# Run the script with the fixtures wired in. Extra env may be passed as VAR=val
# arguments before the script's own flags, separated by --.
run() {
  env TOUCHID_SUDO_TARGET="$FAKE_TARGET" \
      TOUCHID_SUDO_PAM_SUDO="$FAKE_PAM_SUDO" \
      TOUCHID_SUDO_SKIP_ROOT=1 \
      TOUCHID_SUDO_FAKE_VALIDATION="sudo: a password is required" \
      "$SCRIPT" "$@" 2>&1
}

run_broken_pam() {
  env TOUCHID_SUDO_TARGET="$FAKE_TARGET" \
      TOUCHID_SUDO_PAM_SUDO="$FAKE_PAM_SUDO" \
      TOUCHID_SUDO_SKIP_ROOT=1 \
      TOUCHID_SUDO_FAKE_VALIDATION="sudo: PAM authentication error: Module is unknown" \
      "$SCRIPT" "$@" 2>&1
}

assert_contains() {
  local haystack=$1 needle=$2 name=$3
  if [[ $haystack == *"$needle"* ]]; then ok "$name"; else bad "$name" "expected to find: $needle"; fi
}

assert_file_missing() {
  if [[ ! -e $1 ]]; then ok "$2"; else bad "$2" "$1 still exists"; fi
}

head_ "Syntax and static checks"
if bash -n "$SCRIPT"; then ok "bash -n parses cleanly"; else bad "bash -n parses cleanly"; fi
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$SCRIPT" "$SCRIPT_DIR/run-tests.sh"; then
    ok "shellcheck clean (warning and above)"
  else
    bad "shellcheck clean (warning and above)"
  fi
else
  printf '  - shellcheck not installed, skipping\n'
fi

head_ "Informational modes need no root and no config"
rm -f "$FAKE_TARGET"
assert_contains "$(run --help)"    "touchid-sudo — enable Touch ID" "--help prints usage"
assert_contains "$(run --version)" "touchid-sudo 1"                 "--version prints version"
assert_contains "$(run --status)"  "state:       disabled"          "--status reports disabled when no config"
out=$(run --bogus); rc=$?
if (( rc != 0 )); then ok "unknown flag exits non-zero"; else bad "unknown flag exits non-zero" "$out"; fi
assert_contains "$out" "unknown option" "unknown flag explains itself"

head_ "Enable"
out=$(run)
assert_contains "$out" "Wrote"                              "writes the config"
assert_contains "$(cat "$FAKE_TARGET")" "pam_tid.so"        "config contains pam_tid.so"
assert_contains "$(cat "$FAKE_TARGET")" "sufficient"        "pam_tid is sufficient, so password auth still works"
assert_contains "$(run --status)" "state:       ENABLED"    "--status reports enabled"

head_ "Idempotency"
out=$(run)
assert_contains "$out" "Already configured" "second enable is a no-op"

head_ "Preserves unrelated lines"
printf '# hand written\nauth       optional       pam_something.so\n' > "$FAKE_TARGET"
run >/dev/null
assert_contains "$(cat "$FAKE_TARGET")" "pam_something.so" "keeps third-party auth lines"
assert_contains "$(cat "$FAKE_TARGET")" "pam_tid.so"       "still adds pam_tid.so"

head_ "Rollback when PAM validation fails"
cp "$FAKE_TARGET" "$WORK/expected"
out=$(run_broken_pam --disable); rc=$?
if (( rc != 0 )); then ok "exits non-zero on validation failure"; else bad "exits non-zero on validation failure" "$out"; fi
assert_contains "$out" "reverted" "reports that it reverted"
if diff -q "$WORK/expected" "$FAKE_TARGET" >/dev/null; then
  ok "config restored byte-for-byte"
else
  bad "config restored byte-for-byte" "$(diff "$WORK/expected" "$FAKE_TARGET")"
fi

head_ "Disable"
printf '# sudo_local\n# managed by touchid-sudo\nauth       sufficient     pam_tid.so\n' > "$FAKE_TARGET"
out=$(run --disable)
assert_contains "$out" "Removed"                      "removes the file when nothing else remains"
assert_file_missing "$FAKE_TARGET"                    "config file is gone, not a comment-only stub"
assert_contains "$(run --disable)" "Already disabled" "second disable is a no-op"

head_ "Refuses unsupported systems"
printf 'auth       required       pam_opendirectory.so\n' > "$FAKE_PAM_SUDO"
out=$(run); rc=$?
if (( rc != 0 )); then ok "exits non-zero without the sudo_local include"; else bad "exits non-zero without the sudo_local include" "$out"; fi
assert_contains "$out" "Sonoma" "explains the macOS version requirement"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
