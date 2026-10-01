# 0.2.3 Beta security review

Scope: source review, fake-key protocol tests, local Mock UI checks and loopback
redirect integration. Not an independent audit, penetration test or guarantee.

- Production API requests go directly to the configured service. No developer relay or telemetry uploader was found.
- Credentials are in the current macOS user's Keychain, not the app's export/config models. Sharing a macOS login shares app configuration.
- Sessions are ephemeral, without URL cache/cookies/shared credential storage; redirects are rejected.
- Two loopback HTTP servers tested 301/302/303/307/308 for regular and streaming calls: 10 authenticated requests, 0 requests at the redirect target.
- HTTP/transport error fixtures containing fake credentials do not expose them in error output; protocol fallbacks still work.
- Startup configuration uses metadata-only, noninteractive keychain queries. Mock verifies no secret read. Automatic AI tasks may still request authorization.
- Full OS-level multi-account tests, actual keychain ACL inspection, independent security review and notarization remain outstanding.
- Existing macOS keychain compatibility code uses a deprecated noninteractive query constant; no weakening of keychain ACLs is applied.
- Notes and generated text may themselves contain secrets supplied by the user/provider. They are stored/exported as content; do not paste keys into notes.
- Ad-hoc updates may need renewed authorization. Do not solve this by allowing every app to read the key.

Build/test commands are in README. See SECURITY.md for reporting instructions.
