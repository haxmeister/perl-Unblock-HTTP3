# Unblock::HTTP3 0.12

Version 0.12 fixes the CPAN indexing metadata for
`Unblock::HTTP3::NativeABI`.

## Changes

- Give `NativeABI` an explicit module version of 0.12.
- Keep the version of every module in the distribution consistent.
- Check statically parsed versions and generated `META.json` package versions
  in the regression suite.
- Update the release packaging CI check to use the 0.12 archive.

There are no HTTP/3 protocol changes, public API changes, native ABI layout
changes, or dependency changes.

## Release verification

Run the normal GitHub Actions Perl matrix (5.20, 5.28, 5.36, 5.44).
The 5.44 CI job additionally runs `distcheck`, `disttest`, POD checks, and
installed native header checks.

Confirm PAUSE's indexing result separately. The PAUSE database error reported
for the 0.11 upload is independent of the version metadata fix in 0.12.
