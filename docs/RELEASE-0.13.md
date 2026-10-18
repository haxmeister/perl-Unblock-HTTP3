# Unblock::HTTP3 0.13 - release candidate

This is a draft release note. No tag, GitHub release, or CPAN upload has been
created, and the feature branch must pass release CI before publication.

## Changes

- Add bounded buffered request/response body reception and transaction-level
  `on_data` / `on_finish` lifecycle callbacks for high-level integrations.
- Preserve native HTTP3 Transaction and Uniform message identity, with
  per-stream receive-limit failure isolation.
- Require released Net::QUIC 0.05. The HTTP3 QUIC output bridge opts into
  `send_some(..., limit_to_credit => 1)`, limiting accepted bytes to transmit
  capacity and peer flow-control credit. Net::QUIC itself retains its
  standalone transport API and sends targeted capacity-waiter wakeups.
- Remove old development commit pins from all HTTP3 CI workflows.
- Keep the native consumer ABI at version 1.

## Validation before release

- Run the full standalone HTTP3 CI matrix, POD and distribution tests.
- Verify that CI installs Net::QUIC 0.05 from CPAN, not a Git checkout.
- Run quic-go and public HTTP3 interoperability tests and Linux::Event smoke.
- Verify the unified Unblock::HTTP six-producer real-socket regression using
  this HTTP3 candidate and released Net::QUIC 0.05.
- Inspect module-version and META.json indexed provides checks before tagging.

The current released HTTP3 version is 0.12. This candidate is not yet a
released distribution.
