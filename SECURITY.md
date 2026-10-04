# Security

Please do not open a public issue for a security vulnerability before the
maintainer has had a chance to review it.

Report security problems privately to the maintainer through the contact
options on the CPAN or GitHub author profile.

Useful reports include:

- the affected Unblock::HTTP3 version
- a small reproducer when possible
- the expected behavior
- the observed behavior
- whether the issue can cross a trust boundary

HTTP parsing, field validation, Content-Length handling, flow control, and
resource limits are treated as security-sensitive code.
