# LingGanGu AI configuration guide

LingGanGu connects to OpenAI-compatible Chat Completions services. You need a
Base URL, an exact model ID, and usually an API key.

## OpenAI

1. Sign in to [OpenAI Platform](https://platform.openai.com/).
2. Create a key on the [API Keys page](https://platform.openai.com/api-keys).
3. Enter:

| Field | Value |
| --- | --- |
| Base URL | `https://api.openai.com` |
| Model | An exact model ID available to your Platform project and compatible with Chat Completions |
| API Key | The Platform API key you created |

Use an exact model ID from the
[OpenAI model catalog](https://developers.openai.com/api/docs/models), not a
product name such as “ChatGPT” or “Plus.” A ChatGPT sign-in or subscription is
not an API key; API usage is managed by the corresponding Platform project.

## Third-party compatible providers

Copy all three values from that provider's own API documentation or console:

| Field | Value |
| --- | --- |
| Base URL | The provider's root URL or a URL ending in `/v1` |
| Model | The exact model ID assigned by that provider |
| API Key | A key created in that provider's console |

LingGanGu appends `/v1/chat/completions` and avoids duplicating `/v1`.

## Local model servers

The local server must expose an OpenAI-compatible Chat Completions endpoint.
Example:

| Field | Example |
| --- | --- |
| Base URL | `http://127.0.0.1:11434/v1` |
| Model | The exact ID of a model already loaded locally |
| API Key | May be empty for localhost, `127.0.0.1`, or `::1` |

Port `11434` is only an example. Use the address actually exposed by your local
server.

## Correct order

1. Fill in the fields.
2. Select **Save settings**. Saving does not require a network connection.
3. Select **Test connection**. The test may consume a small number of tokens.
4. Enable automatic organization or use the AI workbench only after the test succeeds.

## Common errors

- `401`: invalid, revoked, or incorrectly pasted API key.
- `403`: the key or project cannot use the selected model.
- `404`: incorrect Base URL, `/v1` path, or model ID.
- `429`: insufficient quota or too many requests.
- Timeout/offline: settings can still be saved and local idea capture remains available.

API keys are stored only in macOS Keychain and are excluded from the database,
logs, and exports. LingGanGu asks for confirmation before sending ideas to a new
provider host.

Official references:

- [OpenAI Developer Quickstart](https://developers.openai.com/api/docs/quickstart)
- [OpenAI API Models](https://developers.openai.com/api/docs/models)
- [OpenAI API Overview](https://developers.openai.com/api/reference/overview)
