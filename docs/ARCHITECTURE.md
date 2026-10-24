# QuickDrop architecture and security boundaries

## Preserved foundation

`app/` is a Refena Flutter application. The public UI talks to `packages/localsend_isolates/`, which owns Dart isolates and generated flutter_rust_bridge bindings. `packages/core/` owns the protocol v2 HTTP server/client, TLS identity, multicast, file streams and WebRTC primitives. Those implementations were preserved; this fork does not replace them with UI simulations. Existing translated strings, settings, device favorites, gallery/SAF integration and platform-specific services remain.

`app/lib/quickdrop/` contains the new pairing, vault, history, onboarding and remote-sharing modules. New pages are reached from the home toolbar and Send header. Existing receive/send/progress pages remain the actual transfer workflow. Dark/light themes and system font fallbacks are reused. Internal package and executable names are intentionally retained where renaming would disturb plugin/native integration.

## QuickPair

A QR/text URI includes a local literal IP, port and uppercase SHA-256 certificate fingerprint. Parsing rejects arbitrary public hosts, DNS names, invalid ports and malformed fingerprints. The HTTPS registration and subsequent transfer use the existing pinned client; a different certificate fails before transfer data is sent. The code must come from a trusted device. QR codes are not expiring secrets and there is no remote rendezvous or new trust-on-first-use password protocol. The existing short IP hashtag is a locator, not authentication. In-app camera scanning and deep-link auto-opening are not supplied.

## QuickSpeed and MultiDrop

The existing streaming, checksum, cancellation, retries and per-session state drive real progress/ETA. MultiDrop adds a visible entry point and independent cancellation without inventing parallel sessions outside the existing provider. The selection is reused, but each recipient requires a separate upload; this is not multicast file delivery. The legacy transfer protocol has no byte-offset pause/resume negotiation; partial files are not advertised as resumable. Per-file and per-recipient success must still be assessed from the actual progress/errors screen.

## QuickVault

Vault copies live under the OS application-support directory in `quickdrop-vault/`. `vault.json` stores version, random salt, fixed KDF iteration count and an authenticated key-check ciphertext. `.qdv` files contain AES-256-GCM-encrypted JSON with encrypted filename/content/creation date, a random nonce and authentication tag. Entry IDs are bound as associated data; swapped IDs and modified ciphertext fail authentication. A `.partial` ciphertext is renamed after flush; an interrupted write cannot expose plaintext through this path. External ordinary received files, picker's temporary copies and explicit plaintext exports are outside the vault's protection.

The PIN derives a 256-bit key using PBKDF2-HMAC-SHA256, 600,000 iterations, in a background isolate. The key is held only while unlocked; inactive lifecycle transitions discard the key reference, hide entries and clear PIN fields. An in-flight derivation uses a generation guard so backgrounding cannot unlock the UI later. Five failed PIN attempts impose a persisted five-minute UI retry delay. This cannot prevent offline guessing of a copied vault; use a long random PIN. Managed-runtime memory is not guaranteed to be securely erased, and hardware-backed key sealing/recovery is not implemented. There is no PIN reset that recovers data.

Optional enrolled device biometrics on Android/iOS/macOS are an **additional local-authentication check**, not a replacement encryption key. Its preference is stored outside the encrypted vault, so it is not an offline cryptographic factor. Device biometrics are not tested on this Linux host. Linux/Windows use PIN protection only. Imports are capped at 32 MB because this first format encrypts one complete file in memory; larger chunked-vault formats require a separately versioned authenticated design.

## History and privacy

Sent history stores only names, filesystem/content-URI paths, size/type, recipient alias, date and session outcome. Bytes, previews, transfer tokens and relay credentials are excluded. A serialized persistence queue and latest-snapshot state prevent concurrent recipients or clearing from restoring stale records. Resend reuses a still-accessible original path and returns to normal Send; missing files are reported. Received text bodies are hidden in list/search, but the upstream receive-history persistence still contains message bodies. Users can disable history, clear it or delete files separately; history is not a vault.

## QuickLink

See `quicklink/README.md` for endpoints, trust boundaries and deployment. HTTPS terminates at your relay's reverse proxy. Access capability, optional scrypt PIN and short-lived browser session authenticate downloads; independent management credentials authenticate sender polling/uploads/revocation. There is no file-storage service. Relay TLS is not end-to-end encryption and a malicious relay can substitute content. The sender explicitly chooses and consents to the relay. No local connection failure selects it automatically.

## Platform identity and licensing

Android's application ID and Apple's bundle IDs use `app.quickdrop.transfer`, with corresponding iOS ShareExtension and App Group; development-team IDs are cleared for your own signing setup. Android debug builds add `.debug`. Native method channels and package namespaces retain their original identifiers so plugins continue to function. Windows installer/MSIX and Linux GTK application identities are separate from LocalSend, while internal executable names remain unchanged. Release publisher/store/notarization settings still need owner configuration.

Apache 2.0, upstream copyrights, contributor lists and third-party notices remain. The About page explains the LocalSend foundation. Upstream CI/release scripts, store donation identifiers and published download URLs are historical references and must not be treated as QuickDrop distribution infrastructure.
