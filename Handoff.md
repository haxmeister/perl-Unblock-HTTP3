# ACTIVE FEATURE WORK — HTTP3 CONNECT completion recheck (2026-10-25)

Branch: feature/connect-completion-recheck
Unmodified main baseline: aa810d0b80dd4b3f94850b8ca95a4b5e6d7737a7.
Verified implementation + real-QUIC regression:
b0585f6083c91a7bdfea0ddbccfefea76ab92362
CI: https://github.com/haxmeister/perl-Unblock-HTTP3/actions/runs/40152896247
PASS in all four standalone Perl lanes 5.20, 5.28, 5.36, 5.44.
No main change, merge, tag, version bump, release, or dependent source edits.

Problem: Linux::Event::HTTP real H3 WebSocket Extended CONNECT case
received the full response and remote stream Close but remained active.
At t+1 second: incoming response/reader complete, outbound request
Body::Stream complete, native output_finished, stream closed_seen,
callback_depth 0; Transaction on_finish never occurred before its
5-second timeout. The generic H3 Client completion path requires
that for CONNECT the outbound request body also be complete.

Cause: Body::Stream->complete() used _write_body(final=1) BEFORE
setting its own complete flag. When the final write flushed synchronously,
Connection->_maybe_complete_transaction() observed an incomplete writer
and returned; no later network event was guaranteed to repeat the check.

Fix: After the Body::Stream complete flag is committed, call the new
Transaction->_outgoing_body_complete() internal method. It asks the
existing owning Connection to recheck _maybe_complete_transaction().
Terminal state and callback-depth guards remain in Connection; no
new looping/retry/polling or Linux framework coupling, no new dependency.
The method is triggered once per body finalization, not per chunk.

Test: t/28-connect-completion.t uses real loopback Net::QUIC TLS. A
server sends streaming response DATA and FIN before its Client closes
the outgoing CONNECT request. After consuming the incoming streaming
response, Client request writer->complete must SYNCHRONOUSLY complete
the Transaction and call on_complete/on_finish exactly once, without
additional driver polling. Server finishes normally after receiving FIN.
This test and all existing 28 other standalone tests PASS across the
four CI lanes above.

Downstream verification COMPLETED: root Linux::Event::HTTP
feature/unblock-http-rebuild required CI 40152960105 PASS all seven
Perl jobs, including real Net::QUIC and H3/HTTP2 WebSocket sibling
multiplexing, with t/rebuild/102 passing in BOTH native and Perl
input modes. Existing H3 Stage D tests 70/80/90/95/96/97/98/99
also PASS, plus H1 WebSocket TLS and generic Upgrade/CONNECT tests.
Root exact implementation checkpoint 673584eed55fff7553190c5edc8c52b5c463aa03,
documentation checkpoint 0ca2f480ddfd9d97e7adff13f310c36de0948df4.
The H3 Close regression is no longer a release blocker for the
coordinated feature branches; Stage E generic H2/H3 non-WebSocket
handoff is still pending, as are root throughput/h2spec gates.

Downstream required test:
haxmeister/perl-Linux-Event-HTTP feature/unblock-http-rebuild
t/rebuild/102-websocket-multiplex.t, must pass with the feature source
installed, in both native and Perl input modes. Root CI is pinning the
exact tested commit b0585f6. Verify CI before claiming Stage E green.
Also recheck all existing Stage D real QUIC/TLS tests. H1/2/Net::QUIC
remain read-only.

Permission: user expressly authorized development on a new HTTP3
feature branch to fix this bug. Main still needs permission. Do not
merge, tag, release or bump versions. This note supersedes historical
main release instructions below until a separate release conversation.

---
# MAIN-BRANCH RELEASE HANDOFF: Unblock::HTTP3 0.13
Updated: 2026-10-21
Repository: https://github.com/haxmeister/perl-Unblock-HTTP3
Current branch: main
Integrated development branch: feature/unified-receive-lifecycle
Fast-forward merge checkpoint: 6687bcef0efd11991ac609f7dc7f7fa487153d28

## Instructions for the next HTTP3-only conversation

The maintainer authorized merging the existing coordinated HTTP3 feature
branch to MAIN, and it HAS been fast-forward merged. This is the standalone
Unblock::HTTP3 **0.13 release candidate**. Latest previously published
GitHub version was 0.12. All explicit indexed module versions in this
tree are already 0.13, including HTTP3 NativeABI (important after the
historical PAUSE/NativeABI version-0 indexing incident). Do not
needlessly bump again. No 0.13 GitHub tag/release or CPAN upload has
been performed. Earlier "do not merge", "feature branch only", and
"not release preparation" notes below were written during development
and no longer describe the current MAIN state.

## Independently useful lower-engine contracts

Unblock::HTTP3 is an HTTP/3 engine that remains useful without the upper
Unblock::HTTP or Linux::Event. It integrates with Net::QUIC through
event-loop-neutral datagram/QUIC and timeout contracts. Net::QUIC itself
MUST remain independently usable; do not add upper-layer or Linux::Event
dependencies. Keep direct Client, Server, Transaction and Connection
interfaces available, backed by the original nghttp3/QUIC engines and
Uniform::HTTP objects. The coordinated engine features include:
- Bounded buffered or streamed HTTP3 body receive with per-request
  on_data and on_finish and terminal/lifecycle parity with H1/H2.
- Response streaming via the existing Transaction write/end/on_drain,
  request stream-credit availability notifications, cancellation/error
  isolation, peer SETTINGS and Extended CONNECT support.
- A transport-neutral native fast path while preserving publicly
  installed NativeABI headers and correct VERSION metadata.
- Real-QUIC memory-retention fixes: operation/notification registries,
  weak callbacks, moved weak-slot compaction and FIFO identity tests.
  Keep weak slots WEAK when compacted; pull-only queue entries stay strong.
- Stable live HTTP3 data paths under multiple concurrent request bodies
  and bounded aggregate connection/stream receive windows.
- No built-in WebSocket framing: the optional unified Unblock::HTTP
  layer handles HTTP3 Extended CONNECT and WebSocket sessions.

## Verified checkpoints and dependency boundaries

Production fixes and real-QUIC test source 5e0d496bb52331670edc9850d6fa417d984d0e67
passed standalone CI run 39172069382 and independent quic-go HTTP3
interoperability run 39172069428. One later test-only commit
27eae74797044c3be10137904b6d49388afa9f80 extended the weak
notification compaction test and passed complete standalone Perl
5.20/5.28/5.36/5.44 matrix:
https://github.com/haxmeister/perl-Unblock-HTTP3/actions/runs/39172771475
The integrated HEAD 6687bcef... differs after that passing run only
in Handoff.md. The upper Unblock::HTTP H3 Client/Server/WebSocket
real localhost QUIC/TLS tests and full integration CI were also
verified in the coordinated upper feature before merging.

The current Makefile.PL minimum is Net::QUIC >= 0.05 and
Uniform::HTTP >= 0.06. The Net::QUIC 0.06 minor release candidate,
now on Net::QUIC MAIN, adds a standalone MAX_DATA producer wakeup
fix. HTTP3 0.13 was verified with **published Net::QUIC 0.05** AND
the optional 0.06 feature path; do not silently require 0.06 unless
a real versioned dependency justifies it. This preserves backward
compatibility with an already-published standalone QUIC runtime.
The previous 12/16-producer receive-window stall was fixed with
sufficient aggregate receive-window headroom, NOT by the MAX_DATA
wakeup alone. See historical logs below; avoid repeating that
profiler campaign.

## Next actions in the HTTP3-specific chat

Start from MAIN. Audit version 0.13, Changes, Makefile.PL, all literal
module VERSION values and NativeABI index metadata, MANIFEST, installed
public header, POD, standalone examples, build flags and a clean
disttest from the release candidate tarball. Run/confirm current
standalone and independent interop CI on the source package. Verify
the intended Net::QUIC baseline and correctly express the required
versions in generated metadata; do not regress 0.05 compatibility
without evidence. Complete focused release readiness, obtain approval
for GitHub release/tag and CPAN upload, then validate PAUSE indexes
every package at the correct version. No new performance campaign or
framework-specific adapter work is needed to publish this engine.
HTTP3 0.13 must be available before upper Unblock::HTTP 0.02.

## Historical engineering record (kept for deep debugging; heading above
## supersedes old feature-branch-only restrictions)

## Extra moved-weak-slot lifetime regression passes (2026-10-18)

t/27-callback-queue-retention.t was extended in feature commit
27eae74797044c3be10137904b6d49388afa9f80, without production
changes, to test compaction moving a *still-live* callback-owned weak
slot across an expired slot. It verifies the moved notification remains
weak, a simultaneously moved pull-only entry remains strong, all three
survivors retain FIFO identity, and expired slots disappear. The full
standalone 4-version Linux Perl test matrix 39172771475 PASS (Perl
5.20, 5.28, 5.36, 5.44). The HTTP3 production version used in the
green upper real-QUIC profile remains source commit
5e0d496bb52331670edc9850d6fa417d984d0e67; only t/27 and
documentation have been added afterward. No release/merge/tag/version
change or Net::QUIC modification.

## HTTP3 final weak-notification compaction verified against released Net::QUIC 0.05 (2026-10-18)

HTTP3 feature commit 5e0d496bb52331670edc9850d6fa417d984d0e67
contains the safe in-place weak-preserving compaction and extended t/27.
Full standalone Linux Perl 5.20/5.28/5.36/5.44 matrix GitHub Actions
39172069382 PASS (all four jobs). Independent quic-go client and
external public HTTP3 server interop 39172069428 PASS.

Primary upper haxmeister/perl-Unblock-HTTP feature 9da9a02f... pinned
the exact H3 feature and tested it with **published CPAN Net::QUIC 0.05**.
Complete upper Linux::Event integration 39172126688 PASS: 128 warmup +
2048 measured requests, two isolated rounds, 16 concurrent requests,
alternating 4096/16384-byte responses, exact status/body and callback
validation, all 256-completion memory and registry checkpoints. Unified
ready_transactions stayed at 2-3 queue slots at ALL eight checkpoints
in BOTH rounds (not 2176). Direct ready_transactions stayed at 1-5.
Unified live transactions 1-16, streams 7-22, informational queue zero,
and QUIC TX-buffer 0-240 bytes. At start -> end of measured phase,
unified private KiB R1 7356->7480, R2 7396->7436; direct R1
6340->6416, R2 6292->6364. RSS/PSS nearly flat. Upper complete
distribution suite, all real socket stress (including 12/16 producers
with bounded aggregate credits and the ten-second Reader hold), and
short benchmarking smokes pass. Separate optional standalone Net::QUIC
feature diagnostic upper run 39172126759 PASS as well, but HTTP3 0.13
DOES NOT depend on its unreleased fix.

The upper Client's on_finish cycle was addressed in upper commit
9f47d2b4ea8370f5c215261cbe9474bebaae2801 with a strong
active-operation registry plus weak callback back-references. Unit
tests t/22 prove unretained completed handles/transactions are reclaimed
while caller-held operations retain the actual engine Transaction.
This upper fix and THIS H3 queue fix are both required to reproduce
the successful bounded-memory profile.

Warning: the prior intermediate H3 commit 3f194e... FAILED its matrix
39171819978 because Perl grep created STRONG references from weak
queue entries. Do not revive that implementation; t/27 checks weakness
of moved entries, FIFO, pull-only strong retention, and stale-slot bounds
behind an older live weak head. This compaction occurs once per 64
callback queue insertions (no per-byte overhead). Legitimate unconsumed
pull-only notifications stay strongly owned by contract.

NEXT: The upper branch is adding a matched 2048-request,
three-round profile with checkpoints disabled to examine throughput and
latency without instrumentation overhead; see upper
docs/PERFORMANCE.md. Hosted CI is not a speed-regression gate.
No copy/allocate event rate was measured; the static payload boundary
audit is not an allocation counter. Net::QUIC 0.05 main, both HTTP
engine siblings, and all main branches are unchanged. HTTP3 0.13
is NOT merged/tagged/released.

## Compaction must preserve weak references (2026-10-18)

The initial weak-tail pruning attempt 3f194ec51b19de73a986612763954c4184cb21d6
used grep into a new Perl array. It FAILED t/27 on all four Linux Perl
matrix jobs in Actions 39171819978: copying weak references through
grep promotes surviving references to strong, causing renewed retention
and breaking callback weak-slot expectations. That candidate is NOT valid
for integration/release. The newly added live-head tests exposed it.

This correction compacts the existing Perl array in one forward pass,
testing isweak() before each move, restoring weakness on moved weak slots,
and using splice only to truncate the discarded tail. Pure pull entries
remain strong, callback entries stay weak, order is stable. The test
adds explicit post-compaction isweak assertions for both queue kinds
and strong pull-only elements, in addition to length/FIFO checks.
The compaction is every 64 callback inserts, never per body byte.

Re-run the four-version standalone matrix and independent H3 interop
on this new commit, then update upper integration pins and rerun the
published Net::QUIC 0.05 2048-request profiler. Do not infer success
from the initial failing candidate. No main, tag, release, version bump
or Net::QUIC changes.

## Bounded callback notification queue length (2026-10-18)

The upper unified Client ownership cycle was fixed at upper commit
9f47d2b4ea8370f5c215261cbe9474bebaae2801. Published Net::QUIC 0.05
full real-socket upper CI 39171144266 PASS: 2048 measured requests after
128 warmup, two rounds, with unified private memory 7332 -> 7520 KiB
(round 1) and 7420 -> 7524 KiB (round 2), versus roughly 95 MiB
at end before the upper fix. Direct private memory also stays bounded.
Both modes' active transaction counts remain near the concurrency limit.

One residual diagnostic showed unified ready_transactions ARRAY LENGTH
still equal to 2176, despite bounded private/PSS/RSS memory. A retained
old weak slot at the head can prevent head-only pruning even though all
later weak callback notifications have expired. It did NOT mean 2176
live Transaction objects, but stale queue slots were still accumulating.

This change adds a 64-callback-insertion cadence for compacting expired
weak slots anywhere within ready_transactions and ready_informational,
preserving ordering, intentionally live callback-owned references, and
strong pull-only entries. Existing head pruning remains. The new
t/27 regression holds a live weak head while 512 later weak entries
expire, with a strongly queued pull entry behind the head; it checks
bounded stale slots and FIFO identity for transactions and informational
notifications. This changes no public API, version, native ABI, or
Net::QUIC dependency. The compaction is not in the per-byte hot path.
Large intentionally unconsumed pull-only queues remain strongly held by
contract.

REVERIFY after publishing this HTTP3 feature commit: full four-version
standalone matrix, real-QUIC upper 2048-request profiler (update the
upper workflow pin first), and remaining interop implications. Prior
interop 39165482280 PASS uses identical production engine files except
for this queue-only change. Do not merge, tag, release, or touch main.

## Independent callback/pull queue lifetime regression (2026-10-18)

t/27-callback-queue-retention.t exercises internal notification queues
without a UDP connection: pull-only entries stay strong until retrieved,
callback entries are weak but remain available when the caller still
holds a Transaction, expired entries are skipped/pruned, and informational
notifications follow the same policy. A 128-item callback-only loop
checks queue growth remains bounded. The MANIFEST now includes the new
test and previously documented performance copy-boundary audit. The
live loopback test still validates the real callback and hybrid paths.
Rerun distribution and real-QUIC tests before declaring release ready.

## Native HTTP3 callback notification retention fix (2026-10-18)

Upper sustained real-QUIC profiler on published Net::QUIC 0.05 confirmed
approximately linear direct and unified client private/PSS growth over
2048 completed requests. Live HTTP3 transactions and streams were
bounded near the 16-inflight limit, but ready_transactions retained
2176 strong entries (128 warmup plus 2048 measured) in BOTH modes.
This was an unbounded duplicate strong retention path for callback
users, not evidence of active-stream cleanup failure.

The HTTP3 feature now stores callback-delivered Transaction
notifications as WEAK slots in ready_transactions and
ready_informational. The engine's actual active transaction map stays
strong until terminal/stream close. Pull-only notifications remain
strong, and prompt mixed callback/pull access still works while a
Transaction is alive. next_transaction/next_informational skip expired
weak slots, and insertion drops expired head slots. The server's
on_request callback path is also weak to avoid server-side retention.
No application API method, native ABI or Net::QUIC source changed.

The existing real-QUIC callback/pull loopback regression adds an
assertion that the client callback notification is weak, while the
server's mixed callback/pull identity assertion remains. Client/Server
POD describes the contract. Re-run standalone HTTP3 tests and the
upper same-connection 2048-request profiler against this new HTTP3
commit before claiming memory growth resolved. Update upper integration
CI pin only after verifying the standalone candidate build. No main
merge, tag or release.

## Static payload-copy site audit for HTTP3 0.13 (2026-10-18)

Added docs/PERFORMANCE-COPY-BOUNDARIES.md from the current native source
and published Net::QUIC 0.05. It separates explicit nghttp3 DATA-to-Perl
newSVpvn, nghttp3 output vector-to-Perl sv_catpvn, and Net::QUIC native
transmit memcpy from borrowed pointers and potential Perl COW scalar
construction. Exact copy counts and allocation rates were NOT measured;
the optional upper live profiler memory checkpoints are not substitutes.
No production code, ABI, dependency or main branch changed.

## HTTP3 12/16 Reader stress resolved with bounded QUIC receive credit (2026-10-18)

This SUPERSEDES the earlier handoff interpretation that HTTP3 0.13 needs a
new Net::QUIC release to resolve the aggregate 12-Reader stall.
The original 6-Reader test was valid and remains unchanged.
The 12-Reader exploratory fixture advertised only 458752 bytes of
connection-wide QUIC receive credit while eleven siblings each withheld
about 32739 bytes. The remaining consuming Reader could not release
enough bytes to trigger ngtcp2's coalesced MAX_DATA update. The sender had
zero connection credit, 12 registered send-capacity waiters, usable
per-stream credit and no pending QUIC transmit data. This is a
receive-credit budgeting issue, NOT missing HTTP3 producer fairness.

Upper six/12/16 workload regression now sizes QUIC aggregate credit with
headroom while retaining 32768-byte individual stream windows, the
8192-byte advisory native producer limit, exactly-once callbacks,
per-stream retention accounting, SHA-256 and staged Reader release:
six slow 1-MiB streams at 256 KiB, twelve at 512 KiB, sixteen at 1 MiB.
Additional 32 MiB isolation runs still pass. Independent response
buffering profiles run at up to 32 in-flight. The temporary credit-debug
XSUB was removed from Net::QUIC.

FULL UPPER REAL INTEGRATION on RELEASED CPAN Net::QUIC 0.05: GitHub Actions
39161358835 PASS (all distribution, live TCP/H3 QUIC, extra budget and
profiling smoke stages). Feature-pinned standalone Net::QUIC workflow
39161358785 also PASS. Thus UNRELEASED HTTP3 0.13 requires only published
Net::QUIC >=0.05; no second transport release is a prerequisite.

A separate legitimate standalone Net::QUIC generic activity-wakeup issue
was reproduced and fixed on feature/connection-max-data-wakeup with
HTTP-free t/38. Its clean feature source
1606308eeeaf29f2601fa166046703a4b4ba9491 passed 15/15 CI
39161007332. Net::QUIC main 0.05 remains untouched, and that optional
improvement is not required by the fixed upper H3 stress fixture.

No HTTP3 production source, public ABI, main ref, tag, version or CPAN
release was changed in this investigation. 0.13 remains release-PREPARED,
not released. Other performance work (allocation/copy measurement,
long-duration soak and carefully controlled high-concurrency comparison)
is still open. Do not merge or release without explicit authorization.

## Confirmed HTTP3 16-stream scheduling / tight MAX_DATA gap (2026-10-18)

Upper integration CI 39158428479 at source
7054b96f7207ab8f3f0b6a064c740c2765dd7f23 verified HTTP3 per-stream
output scheduling with 12 and 16 simultaneous 1 MiB producers, independent
32 KiB held Readers (2s and 3s holds), 8192-byte native producer budget,
one authenticated connection and an additional fast response. With
connection_window=33554432 BOTH 12 and 16 producer cases PASS with
the SHA-256, native body retention, producer fair-resume, exactly-once
terminal and sequential Reader credit assertions preserved.

The same CI deliberately FAILS at the 12-producer test when only the
connection receive window is tight (458752). Reader0 obtains 98184 bytes,
others hold 32739 each, 12 H3 output streams are blocked, QUIC send
buffer is empty and native retained body is ~49591. This is a reproducible
aggregate QUIC credit/wakeup concern, not a native body-buffer limit.
No HTTP3-specific ACK broadcast or timer poll workaround is approved.

Unblock::HTTP upper's 32-inflight direct-versus-unified buffered-response
smoke also PASS at 16 KiB responses; initial hosted CI wall ratio ~1.052
over two very short rounds is descriptive, NOT a reliable speed estimate.
Perl allocations and payload copies are still not directly measured.

Potential generic Net::QUIC fix: a standalone 12-stream low-MAX_DATA
reproducer should verify the peer connection-wide MAX_DATA credit update
and targeted wakeup of short-accepted send_some waiters. Net::QUIC 0.05
remains read-only without fresh, separate authorization. Do not merge,
tag or release HTTP3 0.13 yet. No production code or main refs were
changed by this documentation update.
## Resumed 12-producer HTTP3 stress: aggregate QUIC credit gap (2026-10-18)

Do NOT treat HTTP3 0.13 as finished solely on the passing six-producer
release audit. Upper feature extended original real-QUIC pressure fixture
to 12 concurrent 1-MiB producers with independent 32768-byte Reader
windows, held for two seconds, plus a fast request and 8192-byte native
advisory send buffer. All original digest, fairness, retained-body
accounting and completion assertions remain intact.

Upper run 39157872356 confirmed a controlled difference:
- Wide QUIC aggregate connection_window=33554432: 12-producer case PASS.
- Tight aggregate connection_window=458752: 12-producer case FAIL
  with watchdog. Reader0 stops at 98184 bytes, other 11 Readers each
  hold 32739, and QUIC send-retained=0 despite all 12 H3 streams
  remaining output-blocked with native retained-body bytes ~49591.
These received totals are nearly the original aggregate connection
receive window; changing only connection-level credit avoids the stall.

Probable missing wakeup after peer connection-wide MAX_DATA expansion:
the generic Net::QUIC on_stream_activity path includes per-stream credit
and ACK/capacity wakes but may not emit a targeted event when only
connection-level send credit expands. This is a hypothesis pending a
standalone Net::QUIC regression/fix, NOT a proven native C root cause.
Net::QUIC 0.05 remains RELEASED and READ-ONLY. Its modification requires
separate maintainer authorization; do not add HTTP-specific transport
polling or wakeup broadcasts to this HTTP3 engine.

Upper feature 142d2129 now adds a 16-stream wide-window check while
keeping the failing tight-window 12-stream check in CI. Verify its result.
HTTP3 main remains unchanged; do not merge, tag, or release while this
high-concurrency case is unresolved.
## Follow-up release audit: strict dependency version test flaw (2026-10-18)

The project paused before any merge or publication to re-examine unfinished
HTTP3 performance/stress tasks from prior handoffs. Eight distribution tests
still required EXACT Net::QUIC 0.05 despite Makefile.PL declaring 0.05 as a
minimum. This would make the HTTP3 CPAN installation suite fail if a later
compatible Net::QUIC version were installed. Relaxed only these assertions to
require Net::QUIC >= 0.05; CI workflows continue installing/verifying the
actual released Net::QUIC 0.05 for candidate smoke and interoperability.
No engine semantics or other libraries were changed. Re-run full CI before
calling this revision verified.

The six-producer contention and source-pin deadlock regression are resolved,
but sustained very-slow-reader workloads, higher-concurrency reliability and
allocation/copy accounting against direct engine performance remain deferred
in the unified Handoff and docs/PERFORMANCE.md. Profiling tools exist, not a
completed memory/copy budget or stress sign-off. Do not infer all planned
HTTP3 performance work is finished from the released-dependency smoke tests.

## HTTP3 0.13 release verification with released Net::QUIC 0.05 (2026-10-18)

Feature candidate 1bed34bc19213df6066fc72668cf0b9930de0d51:
Net::QUIC 0.05 installed directly from CPAN tarball
(Net-QUIC-0.05.tar.gz; no development source install). The previous
exact-0.04 assertions in seven tests were corrected, without weakening
protocol or producer-flow assertions. Full H3 test workflow 39155065291
PASS all four Linux Perl jobs (5.20, 5.28, 5.36, 5.44). Perl 5.44
also PASS distcheck, disttest of Unblock-HTTP3-0.13.tar.gz, installed
NativeABI smoke and complete public POD syntax checks.

The 0.13 production code was validated in interoperability workflow
39154958488: quic-go independent client and external public H3 servers
both PASS. Optional Linux::Event real UDP/QUIC/TLS example smoke workflow
39154958508 PASS. Benchmark smoke workflow 39154810871 PASS against
CPAN Net::QUIC 0.05 (not a performance gate). These jobs predate the
final version/test-assertion-only cleanup but use identical production
HTTP3/XS code and CPAN Net::QUIC dependency.

Unified upper feature commit 1e1645d6c4d7afbde50adb3ea0bd09deba2ec13c
changed the integration workflow to install CPAN Net::QUIC 0.05 and pin this
HTTP3 candidate 1bed34bc. Upper integration run 39155180473 PASS:
distribution tests, full 13-file real TCP/QUIC smoke set including the
six held 1 MiB HTTP3 producers + independent fast response, 128 KiB and
4 MiB budget variants, and direct/unified benchmark smokes. The original
sha256, progress, fairness, terminal, Reader credit and native-byte
accounting assertions were preserved. No Net::QUIC/HTTP1/HTTP2 source
changes were made for this candidate.

Audit still requires maintainer authorization for merge, tag and publication.
The 0.13 distribution is release-prepared but not released; HTTP3 main is
untouched. Latest changes after verification are documentation-only.

## Net::QUIC 0.05 published dependency and HTTP3 0.13 release candidate (2026-10-18)

Net::QUIC 0.05 has been released to GitHub/CPAN. HTTP3 uses the released
standalone Net::QUIC interface, retaining its optional credit-limited
send_some(..., limit_to_credit => 1) output bridge and generic targeted
capacity-waiter wakeups. Net::QUIC source is NOT modified here.

Release preparation is on feature/unified-receive-lifecycle ONLY. Replaced
Net::QUIC 0.04 dependency/CI verification with 0.05, removed the temporary
feature-commit source installer, and updated all four workflows to use CPAN.
The architecture document now describes the 0.05 credit-aware boundary.
HTTP3 distribution and all 15 Perl module versions are prepared as 0.13;
PAUSE metadata assertions and distribution artifact names are aligned.
Public NativeABI remains version 1; no unrelated public API changes.

The first 0.05 source-free CPAN workflow 39154810862 confirmed successful
Net::QUIC 0.05 download/build and HTTP3 compilation. It found seven
older exact-0.04 test expectations in t/04, t/11, t/13, t/14, t/17,
t/18 and t/24, corrected after the 0.13 versioning commit.
Independent interop 39154810950, Linux::Event smoke 39154810880,
and benchmark 39154810871 passed against CPAN Net::QUIC 0.05,
but those earlier runs preceded the final 0.13 candidate.

This is NOT released or merged. CI, disttest, POD, real-QUIC interoperability,
Linux::Event smoke and upper six-producer published-dependency integration
require fresh verification at this new feature head. Prior source-pinned
CI is historical evidence only. Do not weaken the upper six-producer test.
Main and other repositories are unchanged. Do not tag, merge or publish
without explicit maintainer authorization. Update this handoff with actual
run IDs, results and remaining blockers before release.

# Receive body and lifecycle implementation checkpoint

Updated: 2026-10-17
Repository: haxmeister/perl-Unblock-HTTP3
Branch: feature/unified-receive-lifecycle
Status: receive/lifecycle implementation passes full CI; not a release candidate.

The maintainer explicitly authorized changes to HTTP1, HTTP2, HTTP3 and
perl-Unblock-HTTP. Do not modify main, merge, or release. The user confirmed publication of these
feature branches and coordinated CI on 2026-10-17. Publication is authorized.
The agreed contract is in perl-Unblock-HTTP/docs/ENGINE-CONTRACTS.md.

## QUIC shared-capacity wakeup resolved and tested (2026-10-18)

RESOLVED: upper six-stream test stalled not from exhausted flow credit
but from missing wakeups for QUIC Stream->send_some calls that accepted
only a prefix while the connection-wide send queue was full. Later ACKs
on OTHER streams freed memory, but blocked writers had no own ACK event.
Temporary internal credit probe proved at stall: available MAX_DATA
261956, per-stream MAX_STREAM_DATA ~32 KiB, unsent TX=0, buffered TX=0.
No HTTP3 scheduler broadcast is appropriate. Net::QUIC now tracks only
short-write capacity waiters and wakes those Stream IDs through its
existing coalesced on_stream_activity contract when sibling ACK returns
shared queue space. This is generic standalone QUIC behavior.

Net::QUIC finalized implementation 4d3a45aa2d3efb27523c6733c71d31cf527130a8,
with debug-only private credit API removed. Full 15-job Linux Perl
5.20-5.44/macOS/Windows CI 39147484627 PASS. H3 feature scripts pin
this commit exactly in ccb7759509b76515577fd6270eebbb83d7df0714;
H3 4-job matrix 39147558339 PASS, its previous interoperability and
Linux::Event smoke succeeded. The H3 output bridge alone opts into
limit_to_credit => 1; public H3 API and versions unchanged.

Unified Unblock::HTTP genuine six-slow-producer real-socket regression
PASSED first at upper run 39147266161 (686 live checks in 13 files),
then at cleaned source run 39147574565 after removing temporary
Net::QUIC/XTEST credit probes (also 552 dist, 64+58 buffer-budget and
all profiler smoke checks PASS). The test requires six independent 1 MiB
producers and one fast request, all six initial Reader credit holds,
SHA-256 payload integrity, exactly once terminal completion and native
retention / fairness invariants. No cancellation or weakened constraints.

No main branch changes, merges, releases, tags, or version bumps.
Release preparation in a separate authorized step must first coordinate a
new published Net::QUIC version and H3 minimum dependency requirement;
feature CI source pins are not a valid released dependency contract.

## Opt-in standalone NetQUIC transmit-credit admission (2026-10-18)

User authorized a separate Net::QUIC feature branch but requires Net::QUIC to
remain independently useful (no HTTP/3, Unblock, or event-loop dependency).
Net::QUIC feature/fair-stream-send-capacity preserves the default
Stream->send_some($bytes) behavior exactly, including queueing bytes beyond
peer flow credit. An OPTIONAL named per-call parameter
limit_to_credit => 1 admits only current stream/connection peer send credit
minus all not-yet-sent queued data. It preserves the existing connection
buffer cap and accepted-prefix contract, and newly wakes the existing
on_stream_activity callback when ngtcp2 peer stream credit expands.
Standalone NetQUIC full CI 39146133370 PASS all 15 jobs, Linux Perl
5.20-5.44 and Windows/macOS; no HTTP/3 dependencies or method aliases.

This HTTP3 branch uses the opt-in only inside Connection::_drain_output's
ordinary and SETTINGS QUIC Stream->send_some bridge. Feature source
9d329e2adb64e0a71d58ee549f947b8972190d18. Feature-only CI scripts
pin a confirmed Net::QUIC commit; H3 test and interoperability workflows
39146362177 and 39146357011 PASS, plus Linux::Event smoke 39146362182.
Neither H3 public API nor its version changed. Never use this feature code
with the released Net::QUIC 0.04 unconditionally: release coordination is
not yet approved, and release branches must remain untouched.

The upper six-producer live CI 39146210996 remains RED even with the credit
admission option: two large streams finish, then native H3 output on four
others remains blocked with QUIC retained TX=0. This disproves the idea
that over-queueing beyond peer credit is the only source of starvation.
The upper diagnostic run 39146629367 pins NetQUIC diagnostic-only
commit da9ed57aa46d7bc508afae6601c402fe592b5264 and prints native
MAX_DATA/MAX_STREAM_DATA credit, unsent queue lengths, and blocked IDs.
Inspect before modifying output scheduling again. H3 ACK broadcast retry
experiment was already reverted; do not reintroduce it. No main/merge/tag.

## ACK wakeup experiment reverted (2026-10-18)

The first H3 ACK-driven blocked-output wake experiment
40868d12a343fc217a4aea01199c83ee5e511fe5 did NOT solve the
six-stream stall. Upper CI 39141722608 failed the six-stream test and
also regressed the previously passing three-stream independent-Reader
test. Under multiple uncredited Readers it admitted more QUIC output
without ensuring progress for an actively credited stream. Reverted
Connection.pm exactly to the prior feature source content in
b6f068fde2e279258f9247a7b8c26252245d8008. No ABI/version change.
Reverted HTTP3 full test matrix 39142506332 PASS; interoperability
39142506370 PASS. This is the currently authoritative feature source.
Do not reintroduce sibling ACK unblocking without a demonstrated solution
to the shared QUIC send-buffer saturation. Net::QUIC is read-only.

Upper six-stream probe from CI 39142115478: during the stall, retained
native producer bytes=23634, per-stream=4096,4125,4125,4096,3096,4096,
active=6; blocked_output IDs=0,8,12,16,20; QUIC send_buffered_bytes=8192.
ACK offsets were 36896,32768,32768,24599,1008,5. The currently credited
Reader slow0 had delivered 36864 bytes but was stalled; siblings retained
uncredited Reader data. Native vs QUIC and application receive credit
must be distinguished. This is confirmed congestion/flow-control deadlock,
not evidence of lost or duplicated payload. Root cause in QUIC scheduling
versus H3 output handoff remains open; cannot change Net::QUIC under the
current authorization. The upper reproducer must remain available.

## Six-stream connection-wide QUIC output starvation (2026-10-18)

Upper feature added xt/linux-event-quic-six-credit.t: six independent
1 MiB streamed responses and a fast response on one real authenticated QUIC
connection, under an 8192-byte advisory native retained-body budget.
Each slow pull Reader owns 32768 bytes receive credit, released sequentially.
The original three-stream fixture and the new no-cancellation producer-join
fixtures passed, but six-stream upper runs 39141085484 and 39141149693
reproduced a 60s watchdog: streams 0 and 1 completed, while streams 2-5
accepted one 4096-byte write apiece, got write(false), and never resumed.
The test did NOT weaken the six-producer requirement.

The H3 Connection::_drain_output bridge blocks an nghttp3 stream when
QUIC send_some accepts only part of its pending bytes. Previously,
Connection::_service_stream unblocked only a stream that got its OWN QUIC
send activity. A stream blocked before its first accepted QUIC bytes can
lack its own ACK event, although another stream's ACK has freed shared
QUIC send-buffer room. This can strand nghttp3's blocked writer.

Feature production commit 40868d12a343fc217a4aea01199c83ee5e511fe5
adds _unblock_output_contenders, triggered only when an actual per-stream
ACK offset advances, so all live blocked writers may retry on shared QUIC
send-capacity recovery. The original per-stream flow-control and native
accepted-byte accounting remain unchanged; no looping on permanently
blocked output without new ACK progress. Lifecycle stores last ACK offset
with the existing stream lifecycle state (cleaned up on release).

HTTP3 CI test matrix 39141613551 PASSED (Perl 5.20, 5.28, 5.36, 5.44).
HTTP3 interoperability 39141613659 PASSED (quic-go client and public H3
servers). The upper integration workflow pins this exact engine production
commit at upper source 920eec03ad992766eb2f28a90eca9c5024968173.
Its six-producer live result is not yet verified; inspect the upper run
39141722608 and resolve any remaining starvation before marking complete.
No main, version, tag, release or read-only dependency change.

## Dynamic native producer lifecycle regression (2026-10-18)

Starting feature head da4789e588ff525fda1339002a88aab607752bfb.
Main H3 still 97ef0048be212af34b21a7e1a65b3294f4d34b4c.
Read upper four handoff/contract docs and all engine handoffs.
Only authorized feature branches may change. Net::QUIC and
Uniform::HTTP are read-only.

Added t/01-native assertions for an unfinished first producer,
late arrival of a second producer, native append accounting per
stream, per-stream discard from simulated cancellation, dynamic
active producer count after cancellation and after EOF, retained
body after EOF, and repeated discard without underflow. Native
regression commit e6c1cbb0e54b0dbe40ed6d29e5884e50983a3319
PASSED full HTTP3 test matrix CI 39133563818. The original
streaming producer production source is unchanged. No public
NativeABI or version changes.

Upper unified branch adds xt/linux-event-quic-join-cancel.t, a
real QUIC/TLS test on one connection with 8192 soft native
retention, a held 1 MiB response Reader, a second initially
active producer cancelled mid-response, a late 512 KiB response
joined after cancellation, and an independent fast response.
It tests the retained-body counters, sha256, native
on_drain/accepted-write contract, no duplicate terminal
notification, cancellation idempotency, and buffer isolation.
Upper pinned CI integration run 39133882442 PASSED:
552 distribution checks, 11 real TCP/QUIC files / 485 checks,
64 more checks at the 128 KiB native budget, 58 more at 4 MiB.
The real H3 join/cancel scenario finishes all paths and
receives the expected server/client cancelled terminal state;
repeated cancel is idempotent, native streaming retained body
storage is released, and its per-stream/aggregate counters
reconcile. Deferred producer write(false)/on_drain and SHA256
checks all pass. Upper CI 39134487091 later repeats
the same verified integration fixture successfully while adding
a smoke run for a direct vs unified HTTP3 client benchmark.

Next: active producer join *without* cancelling a sibling,
controlled RSS/allocation and direct-engine comparative
benchmarks with repeated controlled trials and realistic
body sizes. This is NOT proof of a hard memory cap or
a throughput improvement. No main updates, release, merge,
tag, version bump, Net::QUIC or Uniform changes.

## Three-budget retained-byte observation (2026-10-17)

The upper LinuxEvent integration now checks native per-stream
retained streaming body bytes against the connection aggregate
throughout live three-stream producer contention. No production
engine changes beyond tested source
96cf41e9378333fb4f7b48d89c8311c1dcf7cee7.

Upper CI source 556d296392745b7ab16a31b7b213bcf62638aa6b,
run 39098755460 PASSED: 552 distribution / 455 real TCP/QUIC
checks, plus 64 at native send_buffer_limit 131072 and 58 at
4194304. The normal live case uses 8192. No accounting
mismatches in any of the three cases; all requests, byte counts,
SHA-256 digests, staged readers, and once-only producer/terminal
callbacks completed.

Native producer retained peaks observed:
8192 limit -> 13618 bytes; 131072 -> 173406 bytes;
4194304 -> 3047511 bytes. Corresponding sampled QUIC
send-retained peaks were 8192, 131072, 3061953.
Native and QUIC counters measure distinct buffering surfaces,
NOT process RSS or a hard output cap. A whole accepted write
can overshoot its active stream's fair-share budget; the
documented backpressure threshold remains advisory.
Per-stream peaks are not simultaneous values.

Next: tests for active producer join/cancel, native discard/ACK
accounting at stream termination, process RSS and copies, and
controlled direct-H3 versus unified benchmarks. Main,
Net::QUIC, Uniform, release/tag/version unchanged.

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
