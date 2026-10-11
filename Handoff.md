# Unblock::HTTP3 handoff

## Current state

Branch: main
Version: 0.12 prepared, not tagged or published
Last completed work: PAUSE index-metadata correction and 0.12 release preparation

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

## Previous 0.11 verification

- Full test matrix passed on Perl 5.20, 5.28, 5.36, and 5.44.
- GitHub Actions 38105824198 passed; interop run 38105824175 passed.
- distcheck, disttest, POD syntax, installed header, live Linux::Event
  UDP/QUIC examples, and external interop were previously verified.
- These results pertain to 0.11, not fresh 0.12 runs.

## Next steps

1. Verify 0.12 GitHub CI: module test matrix, distcheck, disttest,
   POD syntax, staged installation, and NativeABI header checks.
2. Confirm generated META.json provides version 0.12 for NativeABI.
3. Tag and upload 0.12 only after the audit is complete on user instruction.
4. Verify PAUSE indexing; email modules@perl.org if its database failure recurs.

## Design boundary

- Modify only Unblock::HTTP3 in this workstream.
- One HTTP/3 Client or Server belongs to one Net::QUIC connection.
- Use Net::QUIC::Driver for QUIC packet output, timers and backpressure.
- Start ordinary HTTP/3 operation after QUIC handshake readiness.
- HTTP/3 owns QUIC stream callbacks after start; do not overwrite them.
- Keep Uniform::HTTP pure Perl; preserve optional native fast paths in engines.
- Handoff.md is repository-only, never part of CPAN distribution.
