# Receive body and lifecycle implementation checkpoint

Updated: 2026-10-17
Repository: haxmeister/perl-Unblock-HTTP3
Branch: feature/unified-receive-lifecycle
Status: receive/lifecycle implementation passes full CI; not a release candidate.

The maintainer explicitly authorized changes to HTTP1, HTTP2, HTTP3 and
perl-Unblock-HTTP. Do not modify main, merge, or release. The user confirmed publication of these
feature branches and coordinated CI on 2026-10-17. Publication is authorized.
The agreed contract is in perl-Unblock-HTTP/docs/ENGINE-CONTRACTS.md.

## Fair-share native streamed send retention (2026-10-17 continuation)

This slice addresses the outstanding HTTP3 aggregate-producer starvation
exposed by three separately receive-credit-blocked readers on one QUIC
connection with send_buffer_limit 8192. Main must remain untouched,
and Net::QUIC and Uniform::HTTP remain read-only.

The HTTP3.xs native streaming body now maintains a per-body retained-byte
counter in addition to its existing aggregate counter. The counter changes
on append, ACK and discard/removal. Internal XS accessors expose
streaming_retained_bytes_for_stream(id) and
active_streaming_body_count (unfinished streaming bodies).
No public installed NativeABI layout changes.

Connection->_streaming_share_limit divides the configured native
send_buffer_limit by active streaming producers (minimum one byte).
The write(false) advisory is now based on this stream's retained
bytes versus its share, and _drain_body_producers invokes on_drain
only for a producer whose own stream is below its share. This allows
a consumer resuming stream0 to free its own retained bytes and
wake producer0 even if other QUIC streams remain blocked.
It does not blindly replay rejected writes or alter response identity.

This is a SOFT fairness budget, not an allocation cap. Each write is
accepted in full before the advisory, so one write per active stream
can exceed its dynamic share. A per-stream counter itself does not
bound QUIC retransmission, protocol or process allocations; it also
does not constitute priority scheduling or a memory benchmark.
The same soft send_buffer_limit option and application on_drain
contract remain. Existing single-producer behavior uses the full limit.

Native source commit 21bf5aba9aed9d2b7cae0460718df9ec1421d258;
per-stream producer scheduling f4fc802bd9fcee7fc80e14401aca49a231244bb1;
t/01-native accounting regression 96cf41e9378333fb4f7b48d89c8311c1dcf7cee7.
Run 39098219790 PASSED engine Perl version matrix at scheduler source.
Native source 96cf41e9378333fb4f7b48d89c8311c1dcf7cee7
PASSED full engine Perl matrix CI 39098239956 (including new
per-stream accounting assertions) and production source passed
interop CI 39098219785. Later commits are docs only.

The upper workflow pins native source
96cf41e9378333fb4f7b48d89c8311c1dcf7cee7
and runs xt/linux-event-quic-multi-credit.t with 8192 and again
with 4 MiB native send buffering. Upper 39098276763 proved
the 8192 deadlock was resolved: all three 1 MiB streams finished
with correct hashes, write(false)/on_drain accounting and staged
Reader release. ONE test-only check incorrectly demanded that
all three readers already have nonzero data queued under 8192;
QUIC scheduling initially left Reader2 empty. This expectation
was corrected: some Reader data must be held, each stream
remains incomplete until deliberately drained, and the 4 MiB
isolation case still requires pending bytes in all three.

VERIFIED latest upper run 39098422769 PASS at test source
a545a4ddecef5501e3392dcd3f4f3a4a56223efd:
552 distribution checks, 453 real TCP/QUIC checks at 8192,
plus 56 checks PASS at 4 MiB. Three streams each delivered
all 1 MiB with correct digests and no unwarranted replay;
the fast response completed before slow Readers were released.
Producer false/resume counts matched. Sampled QUIC retained-send
peak was 8192 bytes in this specific small-budget fixture,
3061953 bytes in the deliberately large-buffer isolation fixture.
Those values are NOT general memory caps or speed improvements.

Next: per-stream retained measurements, cancellation/overflow
accounting invariants, high-concurrency stress, process RSS/copy
and controlled direct-H3 vs shared HTTP benchmark. No main,
merge, release, tag, version, Net::QUIC or Uniform changes.

## Independent QUIC output-stream flow control (2026-10-17)

The upper integration xt/linux-event-quic-multi-credit.t exposed a
previously untested situation: three native streamed H3 responses use
one QUIC connection, and all three pull-mode Readers withhold receive
credit. The fast fourth response completed, but releasing the first
slow Reader did not restart its producer. Original upper CI
39095627619 failed after its 45s watchdog (distribution and all
prior live tests passed). The original fixture is retained as a
regression; do not weaken it or mistake that failure for verification.

Root cause identified in Connection->_drain_output: when Net::QUIC
Stream->send_some accepted fewer bytes than offered, nghttp3 retained
the partially written stream as the next eligible output. The bridge
exited the *entire* drain loop without telling nghttp3 that this
stream was QUIC flow-control blocked. Other HTTP/3 streams could
therefore be obstructed.

Fix on this HTTP3 FEATURE BRANCH ONLY:
- HTTP3.xs exposes internal native block_stream()/unblock_stream()
  using nghttp3_conn_block_stream and nghttp3_conn_unblock_stream.
  These are not public NativeABI changes.
- Connection->_drain_output advances the accepted write offset,
  blocks only that partially accepted stream in nghttp3, records its
  id and continues scheduling other streams.
- On next QUIC stream activity, _service_stream unblocks only the
  recorded id; if QUIC still refuses bytes, it reblocks the stream.
  Cleanup deletes per-stream bookkeeping. Other streams remain able
  to progress, with the same accepted-byte contract and no replays.
- No Net::QUIC, Uniform::HTTP, HTTP1/HTTP2, main, or version changes.

Fix source commit 14eaaf2f94173650b830799a2f43fca0c77ab0a1
(preceded by XS commit 2a88fd5f092526985a2fb093dfd9607a2422b951).
Full HTTP3 matrix 39095993708 PASSED on Linux Perl 5.20/5.28/5.36/5.44;
HTTP3 interop 39095993713 PASSED. The first pinned upper regression
39096018997 still FAILED with a 45s watchdog; merely blocking nghttp3
stream selection is NOT a complete fix under this fixture's tiny
global retained-body threshold. Even raising the upper test's global
H3 send_buffer_limit from 8192 to 131072 leaves other stalled
producers consuming aggregate capacity; upper run 39096310032 failed.
With three held Readers, producer0 received 90112 of 1048576 bytes
after release and no further on_drain; two peers remained held.

The H3 send_buffer_limit is a CONNECTION-WIDE native retained-body
threshold, not per-stream fair reservations. Saturating it with
several streams that individually lack credit can prevent an otherwise
unblocked producer from obtaining its next on_drain. Do not claim
independent producer fairness or a global memory cap is solved.
The revised upper fixture uses a 4 MiB cap (larger than its three
1 MiB bodies) to isolate actual QUIC receive-credit independence
from global native send-buffer saturation. The single-Reader
regression still exercises accepted-write producer backpressure
with the 8192 native retained-byte threshold.

The isolated concurrent Reader test PASSED on upper source
ceeca6638e6faf6f2561089fcaaf3d5ad0c626d7, CI
39096607845: 552 distribution checks and 446 real TCP/QUIC
checks. Three Readers were separately held at 32739 bytes
each and subsequently consumed sequentially, with a fast
fourth stream completing before release. Native producers had
already accepted all their 1 MiB bodies under the intentionally
large 4 MiB threshold. This is receive-credit isolation, NOT
a resolution of global producer fairness.

Next: a fair bounded aggregate producer schedule and per-stream
retained accounting. The earlier tiny-global-buffer watchdog
remains a genuine unresolved regression; do not weaken it into
a passing claim.

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

Implemented in Connection.pm with an optional constructor callback
on_request_available($h3_client). Failed open_bidi_stream sets a pending
credit flag before HTTP/3 submits or freezes the request. The engine
remains the sole owner of the QUIC on_stream_available handler, and
invokes the optional callback once after a later 'bidi' event and
internal service. 'uni' events do not wake request writers. GOAWAY,
shutdown, and failed connection states suppress notifications.
No automatic retry or QUIC credit count is fabricated.

New t/26-request-capacity.t checks unsent request mutability, one-shot
wakeup, re-arming after another refusal, event-type filtering, and
shutdown/GOAWAY guards. MANIFEST and Client POD updated. No changes
to Net::QUIC or Uniform::HTTP.

Verified feature source: 9bfd9314fb66f19860a96a20ec6eb082e86e3ce5
HTTP3 full matrix run 39069441321 PASS on Perl 5.20/5.28/5.36/5.44.
Perl 5.44 source tests: 27 files / 959 checks, plus 27 files /
987 checks for disttest. Interop run 39069441276 PASS.
No version bump, release, merge, or main edit. The upper workflow
must pin this feature source for coordinated integration CI.

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
