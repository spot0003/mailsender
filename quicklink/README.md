# QuickLink relay: deployment and trust model

QuickLink is an **optional HTTPS streaming relay**, separate from LocalSend's LAN protocol and the supplied experimental Rust WebRTC signaling server. There is no public default relay. Hosting this server is necessary for QuickDrop's remote-sharing screen to work. No deployment or production credentials were created by the development task.

## Protocol

1. An operator provisions a high-entropy `QUICKLINK_SENDER_TOKEN` (at least 32 characters) securely on the relay. An authorized sender enters it in QuickDrop's QuickLink screen; the app keeps it in memory and never saves it in history or settings.
2. The sender selects files in Send, opts into that relay, selects expiry (15 minutes, 1 hour or 24 hours), a per-file download-attempt limit, and optionally a 6–12 digit PIN. The client hashes the selection without uploading the files, then authenticates a `POST /api/shares` containing filenames, sizes and SHA-256 hashes.
3. The relay returns independent random share ID, access capability and sender-management credential. It stores hashes of the two credentials. The private link is `/s/<id>#<capability>`; its fragment is not sent in HTTP requests. A QR encodes that full link. Send the optional PIN through a separate channel.
4. The browser removes the fragment from its visible URL and exchanges the capability and PIN via same-origin HTTPS `POST /api/shares/<id>/access`. It receives a short-lived bearer download session and the file list only after authentication. No cookie or public metadata API is used.
5. A recipient reserves one file download. The active sender long-polls its management endpoint, sees the request, and streams that file via authenticated HTTPS POST. The server forwards bounded 64 KiB pieces through a two-item queue; it never saves payloads to disk. One active file per share avoids unbounded fan-out. Sender uploads must declare the exact content length.
6. The relay verifies SHA-256 and byte count, withholding final bytes until validation succeeds. A wrong hash or interrupted upload truncates the response. Browser streaming writers abort on failure; they commit only a complete expected-size response. Empty files are served directly after checking their declared empty-content digest. The relay can still read or modify content: this is **not end-to-end encryption**.
7. Expired/revoked shares close active streams; expired state is swept every five seconds. All shares and sessions disappear on process restart. Receiver tokens expire after ten minutes or share expiry, whichever comes first. Limits count **file download attempts**, including interrupted attempts; there is no promise of exactly-once delivery. No byte-range resume is implemented.

A relay failure, NAT/firewall policy, stopped sender or OS background suspension is surfaced as a failed share/download. QuickDrop does not silently upload to storage or switch a local transfer to a relay. Direct WebRTC remote sharing is not implemented; the upstream experimental WebRTC path remains disabled.

## Deployment

Requirements: public DNS under your control, ports 80/443 for Caddy/TLS, Docker Compose or Python 3.12+, a trusted host, and sufficient bidirectional bandwidth. Each transferred byte enters and leaves the relay; outbound traffic may be billed. The host can observe file contents, names, hashes, endpoints, timing and sizes. Infrastructure-level swap, crash dumps, packet capture and logging must be considered in your hosting policy even though application payloads are never written to disk.

1. Edit `quicklink/Caddyfile`: replace `share.example.com` with your DNS name, point DNS to the host, and configure operator contact/TLS as needed. Keep buffering disabled and do not add request-body or authorization logging.
2. Generate a random sender credential locally with a password manager or `python -c "import secrets; print(secrets.token_urlsafe(48))"`. Store it in your deployment secret manager, or a protected untracked `quicklink/.env` for a private deployment. Do not send it in chat, commit it or embed it in the app. Restrict who can create shares; this token authorizes creation but cannot manage another sender's existing share.
3. From the project root: `docker compose -f quicklink/compose.yaml up --build -d`. Use a **single relay worker**; in-memory reservations require process-local routing. Do not add replicas without an independently designed shared-control-plane/routing solution.
4. Verify `https://YOUR-HOST/healthz` returns `{"status":"ok","storage":"none"}` with a trusted TLS certificate. Never bypass certificate checks in QuickDrop. Configure ingress rate/connection limits, a restrictive firewall, resource monitoring, and TLS renewal alerts before opening a public endpoint.
5. Enter the HTTPS origin and sender credential in QuickDrop. Select files, opt in, create a share, and test from a device on a different network. Stop/revoke it and verify subsequent access fails. The Docker/Caddy deployment itself has not been run in this cloud environment.

For local backend development only:

```sh
python -m venv .venv
.venv/bin/pip install -r quicklink/requirements.lock
# Inject QUICKLINK_SENDER_TOKEN through your shell's secure mechanism or secret manager.
.venv/bin/uvicorn quicklink.service:app --host 127.0.0.1 --port 8080 --workers 1 --no-access-log
```

The Flutter client deliberately accepts only an HTTPS origin with no path, query or embedded credential; it does not accept the development HTTP server. To test Flutter end-to-end locally, terminate trusted TLS with your own test reverse proxy/certificate. The automated backend tests use HTTP only on loopback with ephemeral credentials; this is not production transport validation.

## Resource and browser limits

- 256 shares, at most 100 files per share, 10 GiB per file, 128 browser sessions per share, maximum 24-hour expiry, maximum 100 file download attempts. Headers/metadata requests are limited by declared length; also enforce body/connection/rate limits at ingress. PIN derivation uses scrypt; five failed PIN attempts lock the share for 15 minutes. A stolen capability can cause lockout, so keep links private.
- There is one global operator sender credential, not a multi-tenant account/identity system. Run private or controlled deployments until per-user authentication, quotas and abuse controls are independently reviewed. Public internet hardening, load testing and an external security review remain release prerequisites.
- Desktop browsers with the File System Access API stream directly into a user-selected file. Other browsers use a memory-backed download limited to 128 MB to avoid uncontrolled memory use. Large iPhone/Safari downloads are consequently limited in this release. Native QuickDrop receiving of remote shares is not yet integrated; recipients use the included browser page.
- New HTTP sessions and retrying an interrupted file consume a new attempt. Downloads are sequential per share. Range requests do not provide resumable offsets. No offline delivery: the sender must stay active.
- No third-party analytics, fonts, scripts or external assets are loaded by the browser receiver. CSP restricts scripts/styles/connections to self and forbids framing. File names are inserted as text and are never interpreted as HTML or disk paths.

## Test

From the project root, `.venv/bin/python -m unittest discover -s quicklink/tests -v`. The suite covers real HTTP streaming, corrupted data, authentication separation, PIN lockout, expiry, revocation of an active stream, concurrent-download exclusion, attempt limits, empty files, unsafe filenames and browser security headers. See `docs/STATUS.md` for the recorded results and untested deployment/device scenarios.
