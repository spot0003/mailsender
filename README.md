# QuickDrop

A blue-and-white Flutter file-transfer application built on the supplied LocalSend source, with its Rust networking core preserved. This is a development fork, **not a certified production release**. See [validation and remaining work](docs/STATUS.md) before distributing builds.

![QuickDrop icon](branding/quickdrop-icon.png)

## What works in the source

- **Local transfers:** existing account-free multicast discovery, staged scanning, pinned HTTPS/mutual certificates, incoming acceptance controls, files/folders, retries, live speed/ETA and checksum verification.
- **QuickPair:** a local QR/text payload carries an IP, port and certificate fingerprint. Paste a trusted QR reader's decoded text to establish a certificate-pinned connection. Existing short local address codes remain available; these locate a device and are not authentication PINs. No in-app camera scanner is included.
- **QuickSpeed:** existing per-file progress, speed, ETA, retry and cancellation. The LocalSend protocol does not provide byte-offset resume or pause; interrupted files restart. No decorative pause controls are presented.
- **MultiDrop:** enable it on Send and tap each recipient. Existing independent sessions are reused; each active recipient has a cancel control. Files are streamed from the same selection; recipients have separate network uploads.
- **QuickVault:** optional AES-256-GCM encrypted copies, PIN-derived keys using PBKDF2-HMAC-SHA256 (600,000 iterations, random salt), authenticated filenames/content, automatic inactivity lock, explicit plaintext export, deletion confirmation. Optional native biometrics add a second device check on supported Android/iOS/macOS devices; the PIN remains necessary. Vault files are limited to **32 MB each** in this version.
- **Smart History:** searchable received entries and up to 200 sent-file records with recipient, time, size and session outcome; resend existing files and clear records. Disable transfer history in Settings to stop recording. File paths and names in ordinary history are not encrypted; text message bodies are hidden in the received list but remain in upstream received-history storage.
- **QuickLink:** an explicitly selected HTTPS relay, temporary capability links/QR codes, optional PIN, expiration, download-attempt limits, revocation, SHA-256 validation and a browser receiver. The server streams bounded chunks and writes no file payloads to disk. **The relay operator can read file contents; this is not end-to-end encryption.** No automatic relay fallback or third-party object storage. [Deploy your own backend](quicklink/README.md).
- Original icon resources, branded mobile launch screens, responsive themes, light/dark modes and an accessible introduction. Existing translated strings are rebranded; the new feature screens are currently English.

## Start development

Use the existing checkout; each cloud task is already isolated. A separate Git worktree is unnecessary. The uploaded ZIP is the foundation; internal Dart package names and native method channels intentionally keep their LocalSend names to preserve compatibility.

Prerequisites: Flutter **3.41.9** through FVM (Dart 3.11.5), Rust **1.97.1**, a platform compiler, and the platform SDK. Versions are pinned in `.fvmrc` and `rust-toolchain.toml`.

```sh
# From the project root; install FVM if necessary with: dart pub global activate fvm
fvm install
fvm use 3.41.9 --skip-pub-get
cd app
fvm flutter pub get --enforce-lockfile
fvm flutter analyze
fvm flutter test
fvm flutter run
```

The archive includes updated generated translations and models. When changing mapped models or translations, run the existing generators from `app/`:

```sh
fvm dart run build_runner build
fvm dart run slang
```

The isolate package has its own `build_runner` step if its mapped models change. Keep the FOSS-removal markers and the existing Apache/third-party notices.

## Build instructions

- [Windows](docs/BUILD_WINDOWS.md)
- [Android](docs/BUILD_ANDROID.md)
- [iOS — requires macOS and Xcode](docs/BUILD_IOS.md)
- [Linux and macOS](docs/BUILD_DESKTOP.md)
- [QuickLink deployment, authentication and privacy](quicklink/README.md)
- [Architecture and security boundaries](docs/ARCHITECTURE.md)
- [Verification, feature limits and release checklist](docs/STATUS.md)
- [Changed files](docs/CHANGED_FILES.md)
- [Prepared cloud environment](docs/CLOUD_ENVIRONMENT.md)

## Test the preserved networking and new backend

```sh
# Project root
cargo test --locked --manifest-path packages/core/Cargo.toml --features full -j 3
cargo build --locked -p rust_lib_localsend_app -j 3
cd packages/localsend_isolates
fvm flutter test
```

```sh
# Project root, Python 3.12+
python -m venv .venv
.venv/bin/pip install -r quicklink/requirements.lock
.venv/bin/python -m unittest discover -s quicklink/tests -v
```

The backend tests start their own loopback HTTP server with ephemeral test credentials and do not send user files externally. Public deployment requires HTTPS, separate production credentials, DNS, firewall controls and a bandwidth budget. No backend is contacted unless a user creates a QuickLink share.

## Licensing

See [LICENSE](LICENSE), [NOTICE](NOTICE), the existing contributor lists, and bundled package licenses. QuickDrop is a modified LocalSend distribution, not an upstream release. The original [upstream README](docs/UPSTREAM_README.md) is retained as historical documentation; its download links, donation/store identifiers and release recipes refer to LocalSend, not QuickDrop.
