# 灵感菇 · IdeaShroom

[中文](README.md)

A glass mushroom on your Mac desktop: capture ideas, organize and discuss them with AI, and choose what to try next.

> 0.2.3 Beta · macOS 14+ · Apple Silicon only  
> Ad-hoc signed, **not Developer ID signed or Apple notarized**.  
> Source-available under ELv2, not OSI open source. Windows is unsupported; Intel Macs are unverified.

<p align="center">
  <img src="docs/design/assets/linggangu-mushroom-base.png" alt="IdeaShroom glass mushroom appearance concept" width="320">
</p>

Glass mushroom appearance concept. The actual desktop widget has a transparent background and draggable physics bubbles for ideas.

![Workbench with synthetic notes](docs/images/workbench.png)

## Install

After publication, download the arm64 ZIP and matching SHA-256 file from this repository's Releases. The source ZIP is not an application.

Verify with `shasum -a 256 -c LingGanGu-0.2.3-beta-macos-arm64.zip.sha256`, unzip and move the app to Applications. If blocked as an unidentified developer, verify the source first, then follow [Apple's Open Anyway instructions](https://support.apple.com/102445). Do not disable Gatekeeper/SIP or bypass malware/damage warnings.

The menu-bar mushroom opens the workbench, settings and Quit. Closing a window does not quit. See [installation, backup and recovery](docs/INSTALLATION.md).

## Features

- Offline quick capture with Command-Shift-Space; draggable physics bubbles.
- SQLite storage, search, explicit editing, user tags, archive, Markdown/JSON export.
- Pending, Want to do, In progress, Completed and Archived. All includes archives.
- AI annotation, scoped summaries, streaming conversations and local history.
- Read-only idea evaluation, arguments for/against, minimal experiment, report export and linked discussion.
- AI suggestions never automatically change workflow status or execute external actions.

## API and privacy

Configure your provider's Base URL, exact model ID and own API Key. Save, then test. OpenAI-compatible Chat Completions only; not every vendor/model is compatible. See [API setup](docs/AI_CONFIGURATION_GUIDE.en.md).

Keys remain in the local user's macOS Keychain. Requests go directly to the configured provider, never through a developer relay. There is no hosted account system, shared credential pool, telemetry upload or cloud sync. Sharing one macOS login also shares the app configuration.

Production sessions use no persistent cache/cookies and reject redirects. Selected notes and required discussion/report context go to the provider. Automatic annotation defaults off. API usage/retries may cost money. A provider necessarily receives the authentication key; choose a trustworthy endpoint. Secrets pasted into note text are ordinary content and will be stored/exported.

Ad-hoc updates can trigger new keychain authorization. Do not allow all applications to access your key as a workaround.

## Limitations and development

No notarization or auto-updater. The local SQLite database is not separately encrypted by the app. No one-click JSON import or independent crash-recovery journal; retry failed reply saves before quitting. Evaluation does not perform market research or predict success.

Swift 6+ required; full Xcode for XCTest:

```bash
swift build
swift run LingGanGuCoreChecks
swift run LingGanGu --ui-smoke
python3 Scripts/check-api-redirects.py "$(swift build --show-bin-path)/LingGanGuCoreChecks"
swift test
bash Scripts/build-beta.sh
```

UI smoke requires a graphical login and uses Mock/temp storage. Redirect checks use loopback and fake keys. Beta artifacts are placed in dist; no upload occurs. CI/XCTest status must be checked in Actions; local CLI checks are not a substitute.

Copyright © 2026 Huo_miao. [ELv2](LICENSE), [commercial restrictions](COMMERCIAL_USE.md), [asset/dependency notices](THIRD_PARTY_NOTICES.md). Issues only before v1; no external PRs. Never post keys/private notes. See [security policy](SECURITY.md), [public plan](PLANS.md) and [release notes](docs/RELEASE_NOTES.md).
