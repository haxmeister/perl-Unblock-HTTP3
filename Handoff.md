# Receive body and lifecycle implementation checkpoint

Updated: 2026-10-17
Repository: haxmeister/perl-Unblock-HTTP3
Branch: feature/unified-receive-lifecycle
Status: receive/lifecycle implementation passes full CI; not a release candidate.

The maintainer explicitly authorized changes to HTTP1, HTTP2, HTTP3 and
perl-Unblock-HTTP. Do not modify main, merge, or release. The user confirmed publication of these
feature branches and coordinated CI on 2026-10-17. Publication is authorized.
The agreed contract is in perl-Unblock-HTTP/docs/ENGINE-CONTRACTS.md.

## H3 request stream credit continuation (2026-10-17)

Starting feature refs: upper e540559ca43bce8b15fc8c71d148f82e863ca858;
HTTP3 e35bd69874cb45ea37094cf58e9ed807b46ad6d9.
Upper CI 39065824604 is green. All main refs unchanged.
GitHub connector is the branch-specific publication path.

Design: Net::QUIC::Connection already emits an on_stream_available
callback with 'bidi' and 'uni' event types. HTTP3 must keep its existing
ownership of that callback and forward a narrowly scoped
on_request_available($h3_client) notification only after request()
previously returned undef because open_bidi_stream yielded no stream.
Events for uni streams or unrelated activity do not notify. The HTTP3
callback is advisory, not a persistent stream-credit counter. HTTP3
retains transport/flow-control ownership and no Net::QUIC modifications.

Unblock::HTTP Client must preserve a failed-to-admit (unsent) request
in its finite queue, not report an error or construct a fake tx.
Mark that H3 engine credit-blocked until it notifies; then defer the
scheduler through the framework and reattempt only the still-unissued
request. The real transaction remains the engine's returned object
once admitted. Strict version and timeout/cancel rules remain intact.
No automatic retry for any dispatched request.

Tests: H3 engine fake QUIC bidi exhaustion and bidi/uni notifications;
upper deterministic blocked queue, callback wakeup, cancellation and
per-origin caps; CI for the H3 feature and upper pinned integration.
Update the upper CI pin only to a verified H3 feature source SHA.
No release, version bump, merge, or changes to main.

This is an implementation plan until verified CI results are recorded.

## Implemented

- Bounded buffered reception and per-transaction on_data streaming selection.
- Client request options on_data and on_finish; server registration at headers.
- Exactly-once terminal notification after completion/error callbacks; terminal
  observer exceptions are ignored. Cancellation is distinct from an error.
- The same native engine transaction and Uniform message are retained.
- Buffered data is installed before completion/freeze; failed buffers are freed.
- Bodyless messages already frozen at headers carry an empty body string at
  construction. Public native ABI layouts/discovery paths are unchanged.
- Default receive modes remain H1/H2 stream, H3 buffered; buffer cap is 64 MiB.

H3 reuses Body::Reader and existing owned receive chunks. Overflow now resets
only its stream. Streamed messages are frozen before on_request_end.

## Validation

Three local test files pass: t/01-native.t, t/15-receive-body-ownership.t,
and t/25-terminal-callbacks.t (92 top-level tests/subtests). XS was built using
upstream nghttp3 d29ceea176cebc1f41c9d818c3b1825143d3f813 (1.18.90 development).
Test-Simple and Term-Table were loaded from read-only source checkouts.
Net::QUIC is still unavailable, so full H3/live QUIC tests have NOT run locally.
New live regression source: t/24-receive-lifecycle.t. Run the full existing
test.yml workflow using released dependencies before calling H3 verified.

Local reproduction (from this repo):
  LD_LIBRARY_PATH=../deps/nghttp3
  PERL5LIB=../deps/Uniform-HTTP/lib:../deps/Test-Simple/lib:../deps/Term-Table/lib
  prove -bl t/01-native.t t/15-receive-body-ownership.t t/25-terminal-callbacks.t

The scratch /tmp/http3-source-Makefile.PL supplies upstream native build flags;
the repository Makefile.PL is unchanged. Body::Reader cancellation now returns
queued receive credit. Reader completion defers terminal notification until
both request-end and Reader on_end callbacks have unwound.

No performance or zero-copy improvement is claimed. Version numbers are
unchanged; this is a coordinated development branch, not a CPAN release.

## Resume

1. Check git status/branch and inspect the diff; main must remain unchanged.
2. Local source/POD review and focused tests are complete; inspect the recorded
   validation limits before continuing with CI.
3. Feature branch is published, tree verified and full CI passed (see below).
4. Coordinate remaining unified verification using the upper handoff.
5. Update upper-layer CI pins to the published engine commits and run live
   Unblock::HTTP integration. Upper Server now maps on_headers to engine
   on_request and application on_request to engine on_request_end.
6. Preserve frequent handoff updates. WebSocket, transaction_class, pause/resume,
   and client pooling are later milestones; no changes to Net::QUIC authorized.

## Verified feature publication

Tested source: 3824e7b91012f2a73143ca46eb0d077db6d1af6a
Full suite: https://github.com/haxmeister/perl-Unblock-HTTP3/actions/runs/39059118633
PASS on Perl 5.20, 5.28, 5.36 and 5.44: 26 files / 942 top-level tests/subtests.
Perl 5.44 also passed distcheck, disttest, staged NativeABI/header installation
and POD syntax. Dependencies were the released Net::QUIC 0.04,
Alien::nghttp3 0.01 and Uniform::HTTP 0.06.
Interop: https://github.com/haxmeister/perl-Unblock-HTTP3/actions/runs/39059118732
PASS for independent quic-go client and public HTTP/3 servers.

CI exposed and fixed cancellation reset bookkeeping: rejected payload is
discarded while QUIC reset/close processing and normal cleanup continue.
STOP_SENDING already returns credit for delivered/unconsumed bytes in Net::QUIC;
terminal Reader cleanup and rejected native events must not credit them twice.
The live tests now use refaddr for identity and stream-local overflow assertions.
No Net::QUIC changes were needed. The dependency checkout is read-only.

Upper integration run 39059172525 pins this tested commit and PASSED:
182 distribution checks and 15 live H1/H2 TCP and H3 QUIC/TLS checks.
The coordinated ordinary Server milestone is verified. Main remains unchanged.
Subsequent handoff-only commits do not require changing the tested source pin.

## Historical handoff (superseded)

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

## 2026-10-17 CI correction checkpoint

Published initial engine commit d486f682530b436f4dc00f532f80cac669236db6.
Full test run 39058707266 exposed rejected-stream bookkeeping skipping the
peer reset code after cancellation; service now discards rejected payload
but continues reset/close processing and normal terminal cleanup.
Updated t/04 overflow expectations for the agreed stream-local failure scope.
Changed new t/24 object identity checks to refaddr, avoiding Test2 deep
comparison recursion through the connection graph. Awaiting new CI run.

The replacement full run 39058891647 confirmed cancellation reset bookkeeping
is fixed, but exposed receive credit returned twice after STOP_SENDING.
Net::QUIC discards and credits delivered/unconsumed bytes when stop_sending
runs. Terminal Reader cleanup and rejected queued native events now skip
credit already returned there. No Net::QUIC changes were made.
The overflow test now clears prior deliberate error state before waiting.
Interop run 39058891709 passed. Awaiting the next full test run.
