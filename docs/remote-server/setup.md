# Setup & Security

## Enabling the server

The Mobile server is **disabled by default**. Toggle it from **Settings → Mobile** on macOS.

| Setting | Default | Notes |
| --- | --- | --- |
| Enable Mobile Server | off | Starts/stops the secure WebSocket listener. |
| Port | `4865` | Stored in `UserDefaults`, applied on start. Bind failures roll the toggle back off. |
| Approved devices | empty | List of paired clients with per-device scope toggles and revoke buttons. |
| Remote audit log | read-only | Recent destructive remote VCS attempts from the local JSON Lines log. |

## Endpoint

- Protocol: Secure WebSocket
- URL: `wss://<host>:<port>`
- Encoding: UTF-8 JSON
- Date format: ISO 8601
- IDs: UUID strings

## Security model

The API is designed for trusted local networks.

- Transport is `wss://` with a Muxy-generated self-signed server certificate.
- Pairing URIs include `transport=wss`, `protocolVersion=2`, and `certFingerprint`.
- Companion clients must pin the certificate fingerprint from the pairing URI and reject certificate mismatches.
- Clients must authenticate before any other RPC.
- Protocol v2 authentication uses a server-issued nonce, server timestamp, device fingerprint, and HMAC response.
- Successful authentication returns a session token. Clients must send it on every post-auth request.
- Each approved device has remote capability scopes. Existing and newly approved devices default to all non-admin scopes; `admin` is reserved.
- Every post-auth RPC is checked against the authenticated device's scopes before dispatch.
- The first destructive remote VCS action in each WebSocket session requires local confirmation on the Mac.
- Every destructive remote VCS attempt is appended to `~/Library/Application Support/Muxy/audit/remote.log`; the file rotates at 10 MB and keeps five rotated files.
- New devices must be approved from the Mac before they become trusted.

For production integrations, still treat the connection as local-network only unless you provide your own secure tunnel such as Tailscale or a VPN.

## Error codes

| Code | Meaning |
| --- | --- |
| `400` | Invalid parameters |
| `401` | Authentication required, missing session token, or missing method capability |
| `403` | Pairing denied or local destructive-action confirmation denied |
| `404` | Resource not found |
| `408` | Pairing request timed out |
| `500` | Internal error or operation failure |

## Integration recommendations

- Persist `deviceID` and the pairing token securely.
- Do not persist `sessionToken`; it is scoped to the current WebSocket session.
- Re-authenticate after reconnecting.
- Treat `workspaceChanged` as authoritative.
- Cache project logos after decoding the Base64 payload.
- Call `takeOverPane` before interactive terminal control.
- Handle `401` by re-authenticating when the session token is missing or expired; if auth succeeds and a method still returns `401`, treat it as a missing capability until the user changes the device scopes and reconnects.
- Handle `403` on destructive VCS calls as a local operator denial. Do not retry in a loop.
- Server-pushed events are filtered by the same capability model.
