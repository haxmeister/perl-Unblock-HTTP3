# Unblock::HTTP3 0.14 - release preparation

**Status: release candidate only**. The maintainer authorized merging the
complete `feature/connect-completion-recheck` changes to main and
bumping the distribution to 0.14. Tagging, publishing a GitHub release
and uploading to CPAN remain separate steps requiring explicit approval.

## Changes

An HTTP/3 CONNECT response could finish, with the incoming reader,
outgoing writer and native stream all completed, yet the Transaction
remained active because the final Body::Stream write flushed before
the writer's `complete` flag was set.

After marking the writer complete, the engine now rechecks the ordinary
Transaction completion conditions. This preserves exactly-once
terminal callbacks and avoids reliance on another QUIC/network event.
The fix is event-loop-neutral. See `t/28-connect-completion.t`.

## Compatibility

- All 15 Perl modules use the statically parseable version **0.14**.
- Native HTTP/3 consumer ABI remains at version **1**.
- Minimum Perl 5.20, Alien::nghttp3 >= 0.01,
  Net::QUIC >= 0.05 and Uniform::HTTP >= 0.06.
- No public API additions and no Linux::Event-specific code.
- No Net::QUIC or sibling HTTP engine modifications.

## Release checks

- Test matrix: Perl 5.20, 5.28, 5.36 and 5.44.
- Real QUIC/TLS CONNECT regression and existing HTTP/3 loopback suite.
- `make distcheck`, `make disttest`, `t/23-pause-indexing.t`.
- Generated `META.json` provides must index all public modules at 0.14.
- Installed native header must be accessible from built source archive.
- `.github/workflows/test.yml` archive paths must name 0.14.

Do not publish until required workflows are green. This document
does not represent a completed CPAN upload or GitHub release.
