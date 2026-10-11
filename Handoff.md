# Unblock::HTTP3 handoff

## Current state

Branch: main
Version: 0.12 prepared, not tagged or published
Last completed work: PAUSE metadata fix and successful 0.12 release audit

## 0.12 changes

- Fixed Unblock::HTTP3::NativeABI's static version declaration. PAUSE
  previously found version 0 when scanning a dynamically assigned VERSION.
- Updated version numbers across all 15 Perl modules.
- Added t/23-pause-indexing.t to check statically parsed module versions and
  META.json provides when distribution metadata is available.
- Updated the version-specific installed NativeABI packaging check in CI.
- Updated README, Changes, and release documentation.
- No protocol, C ABI, Perl application API, or dependency changes.

## PAUSE incident

- The 0.11 PAUSE indexer email said "Database error occurred during index
  update" even though the public modules were individually marked indexed.
- It also rejected NativeABI version 0 because 0.03 had previously been indexed.
- The 0.12 NativeABI fix addresses the version regression, not the independent
  PAUSE database error. Confirm PAUSE indexing health after release.

## 0.12 release audit

- GitHub Actions test run 38171242419 passed on Perl 5.20, 5.28,
  5.36, and 5.44.
- Perl 5.44 passed distcheck, disttest, POD syntax, staged installation,
  and the installed NativeABI/header checks.
- t/23-pause-indexing.t passed both the source test run and disttest
  from the generated Unblock-HTTP3-0.12 distribution.
- GitHub Actions interop run 38171242402 passed the external quic-go
  client and public HTTP/3 server checks.
- Linux::Event live example run 38171242376 passed.
- MANIFEST includes the new regression test; MANIFEST.SKIP excludes
  Handoff.md and repository-only release notes.
- The previous 0.11 PAUSE database error cannot be validated from CI.
  Check PAUSE separately after upload.
- This is ready for a 0.12 GitHub/CPAN release once the user elects to
  tag and publish it.

## Next steps

1. Tag v0.12 and upload Unblock-HTTP3-0.12.tar.gz when authorized.
2. Verify PAUSE's 0.12 indexing email, particularly NativeABI 0.12.
3. Contact modules@perl.org if the PAUSE database update error recurs.

## Design boundary

- Modify only Unblock::HTTP3 in this workstream.
- One HTTP/3 Client or Server belongs to one Net::QUIC connection.
- Use Net::QUIC::Driver for QUIC packet output, timers and backpressure.
- Start ordinary HTTP/3 operation after QUIC handshake readiness.
- HTTP/3 owns QUIC stream callbacks after start; do not overwrite them.
- Keep Uniform::HTTP pure Perl; preserve optional native fast paths in engines.
- Handoff.md is repository-only, never part of CPAN distribution.
