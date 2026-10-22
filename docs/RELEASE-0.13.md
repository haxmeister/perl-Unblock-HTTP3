# Unblock::HTTP3 0.13 - release candidate

The 0.13 release candidate is on `main`; the last published version is 0.12.
No 0.13 GitHub tag/release or CPAN upload has been made. This file records
release preparation, not authorization to publish.

## Changes

- Add bounded buffered request/response body reception and per-transaction
  `on_data` / `on_finish` lifecycle callbacks. Preserve common lifecycle
  behavior across the HTTP1, HTTP2, and HTTP3 engines.
- Preserve native HTTP3 Transaction and canonical Uniform message identity,
  with receive-limit failure and cancellation isolated per HTTP/3 stream.
- Use the published Net::QUIC 0.05 credit-limited
  `Stream->send_some(..., limit_to_credit => 1)` option in the output bridge.
  Preserve fair producer wakeups and independent Net::QUIC operation.
- Prevent unbounded retention of completed callback-delivered Transactions:
  store callback notification entries weakly, compact expired weak slots
  without strengthening surviving references, and preserve FIFO order.
  Pull-only notifications remain strongly owned until retrieved.
- Add queue-retention and receive-lifecycle regression tests, including
  weak-slot compaction and mixed callback/pull access.
- Keep the public native consumer ABI at version 1, its installed C header,
  and the direct Client, Server, and Transaction interfaces.
- Remove development-specific source pins from release CI. Continue to
  require only published Net::QUIC >= 0.05 and Uniform::HTTP >= 0.06.

## Existing validation

- The standalone test workflow passed on Perl 5.20, 5.28, 5.36, and 5.44:
  https://github.com/haxmeister/perl-Unblock-HTTP3/actions/runs/39172771475
- The Perl 5.44 job passed `distcheck`, `disttest`, installed native-header
  checks, and POD syntax checks using released CPAN dependencies.
- Independent interoperability against public HTTP/3 servers and a quic-go
  HTTP/3 client passed:
  https://github.com/haxmeister/perl-Unblock-HTTP3/actions/runs/39172069428
  Only tests and documentation changed after the production source used
  for this interoperability run.
- The PAUSE indexing regression checks all 15 Perl module versions and
  the indexed `META.json` provides entries, including NativeABI.
- Unified real-QUIC memory and receive-window regression work was verified
  with released Net::QUIC 0.05 before the source was merged to `main`.

## Final publication checklist

- Confirm the standalone CI matrix on the final `main` documentation commit,
  including the distribution and native-header installation checks.
- Confirm the intended interop and Linux::Event smoke results, and inspect
  packaged `META.json` / `MANIFEST` before uploading.
- Obtain maintainer authorization before creating a GitHub tag/release or
  uploading to CPAN.
- After the CPAN upload, confirm PAUSE indexes every public package,
  especially `Unblock::HTTP3::NativeABI`, at version 0.13.
