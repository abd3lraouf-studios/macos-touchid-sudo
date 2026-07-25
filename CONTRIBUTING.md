# Contributing

Thanks for helping out. This tool edits the authentication path of `sudo`, so the bar for changes is "cannot lock anyone out", ahead of features.

## Ground rules

1. **Never make `sudo` unusable.** Every change to how `/etc/pam.d/sudo_local` is written must keep the backup → validate → rollback sequence intact.
2. **`pam_tid.so` stays `sufficient`, `pam_reattach.so` stays `optional`.** Both choices exist so that failure degrades to password auth instead of denying access. A PR that makes either `required` will not be merged.
3. **Never hand-edit `/etc/pam.d/sudo`.** macOS updates overwrite it. If the `sudo_local` include is missing, the correct behaviour is to refuse and explain.
4. **No new runtime dependencies.** Bash 3.2 (macOS system bash) plus the base system. `pam-reattach` is optional and detected, never required.

## Setup

```bash
git clone https://github.com/App-Builders-Gang/macos-touchid-sudo.git
cd macos-touchid-sudo
brew install shellcheck
make test
make lint
```

Both must pass before you open a PR. CI runs them on macOS and will fail the build otherwise.

## Tests

`tests/run-tests.sh` runs the real script against fixture files in a temp directory — no root, and nothing under `/etc` is read or written. It works through environment hooks that exist purely for testing:

| Variable | Purpose |
|---|---|
| `TOUCHID_SUDO_TARGET` | path to manage instead of `/etc/pam.d/sudo_local` |
| `TOUCHID_SUDO_PAM_SUDO` | path to check for the include line instead of `/etc/pam.d/sudo` |
| `TOUCHID_SUDO_SKIP_ROOT` | skip the root check and `chown`/`chmod` |
| `TOUCHID_SUDO_FAKE_VALIDATION` | stand in for the output of the real `sudo -n` probe |

Do not use these outside tests, and do not add hooks that let the script skip validation in real runs.

Any behaviour change needs a test. Add assertions with the existing `assert_contains` / `assert_file_missing` helpers and keep each check to one observable behaviour.

## Manual verification

The suite deliberately cannot cover the parts that need root and real hardware. Before releasing, verify by hand on a Mac with Touch ID:

- [ ] `sudo touchid-sudo` on a machine with no `sudo_local` — Touch ID then prompts for `sudo true`
- [ ] Re-running reports `Already configured`
- [ ] `sudo -k && sudo true` **inside tmux** prompts for Touch ID (needs `pam-reattach`)
- [ ] `sudo touchid-sudo --disable` removes the file and password auth still works
- [ ] SSH into the machine — `sudo` falls back to a password prompt rather than failing

## Pull requests

Keep them focused; one behaviour per PR. Explain what you verified by hand, since CI cannot test the PAM stack itself. Match the existing style: comments explain *why* a choice was made, not what the line does.

## Reporting a security issue

Open a regular issue for bugs. For anything that could be used to bypass authentication or lock a user out, email the maintainers rather than filing publicly.
