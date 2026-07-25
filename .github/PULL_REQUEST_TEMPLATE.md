## What does this change?

<!-- One or two sentences. Link any related issue. -->

## Why?

<!-- The problem this solves. -->

## Verification

- [ ] `make lint` passes
- [ ] `make test` passes
- [ ] Tests added or updated for the behaviour change
- [ ] Verified by hand on a Mac with Touch ID (say which of the CONTRIBUTING.md manual checks you ran)

## Safety

- [ ] `pam_tid.so` remains `sufficient`, `pam_reattach.so` remains `optional`
- [ ] The backup → validate → rollback sequence is intact
- [ ] `/etc/pam.d/sudo` is not modified
