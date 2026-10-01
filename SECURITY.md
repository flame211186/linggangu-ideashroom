# Security policy

## Supported versions

There is no public stable release yet. Security fixes target the latest code on
the `main` branch.

## Reporting

Until a private security contact is published, open a GitHub Issue containing
only a non-sensitive summary and request a private contact channel.

Never include:

- API keys or authorization headers;
- exported ideas or databases;
- personally identifying note content;
- an exploit payload that would expose another person's data.

## Security guarantees

0.2.3 uses an ephemeral API session with redirects rejected, no persistent URL cache,
cookie storage or credential storage. Server error bodies are not exposed as diagnostic
messages. Configuration loading checks keychain metadata without requesting secret data
or authentication UI. Actual AI tasks can still require keychain authorization.
Ad-hoc builds may prompt again after updates; Developer ID signing/notarization remains
pending. See docs/API_SECURITY_REVIEW.md for test coverage and limitations.

- Idea capture works without network access.
- API keys are stored in macOS Keychain, never in SQLite or exported data.
- Remote AI endpoints must use HTTPS; loopback endpoints may use HTTP without a key.
- The first content request to a provider host requires explicit confirmation showing
  the destination and number of ideas.
- AI requests contain only the idea scope selected by the user.
- Provider errors are redacted before display and do not include the configured API key.
- AI failures never overwrite original idea text or block local capture.
- Theme packages contain data and assets only; executable theme code is rejected.
