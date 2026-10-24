# iOS build and signing

**Building, signing and distributing an iOS application generally require macOS and Xcode.** Linux cannot produce a validated signed IPA. Use a physical iPhone for network, background, file picker and Face ID/Touch ID tests.

Install the current compatible Xcode, its command-line tools, CocoaPods, FVM and Rust 1.97.1. From the project root:

```sh
fvm install
rustup toolchain install 1.97.1 --profile minimal
rustup target add --toolchain 1.97.1 aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
cd app
fvm flutter pub get --enforce-lockfile
cd ios
pod install
open Runner.xcworkspace
```

In Xcode, choose **your own Apple development team** for Runner and ShareExtension. The upstream team was cleared. Register the bundle IDs `app.quickdrop.transfer` and `app.quickdrop.transfer.ShareExtension` (or change them consistently to IDs you own) and the shared App Group **`group.app.quickdrop.transfer`**. Enable that same group for both targets and configure matching provisioning profiles.

Existing local-network usage strings, Bonjour/multicast setup, file access and share-extension permissions remain intact. `NSFaceIDUsageDescription` explains the optional additional QuickVault authentication check. A PIN remains required for encrypted vault access.

```sh
# From app/, after selecting valid signing/provisioning settings
fvm flutter build ios --debug --no-codesign  # compilation check only
fvm flutter build ipa --release             # requires signing configuration
```

Do not assume the OS will keep receiving or serving QuickLink in the background. Keep QuickDrop open; retry a complete interrupted file. iOS saves into its app sandbox or user-chosen document-provider locations, not unrestricted filesystem paths. Biometrics, share-extension delivery, local-network permission prompts, QR text-copy workflow, and vault import/export still need physical-device tests.
