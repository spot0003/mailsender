# Android build

Install Android Studio/SDK, Java 17, FVM, Rust 1.97.1, and the Android NDK requested by Flutter/cargokit. The supplied Gradle project specifies compile SDK 36 and target SDK 37; install those SDK levels, or review a coordinated SDK update as a separate platform change. Do not silently lower the target. Native minimums are determined by Flutter and plugins.

```sh
# Project root
fvm install
rustup toolchain install 1.97.1 --profile minimal
rustup target add --toolchain 1.97.1 aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cd app
fvm flutter pub get --enforce-lockfile
fvm flutter analyze
fvm flutter test
fvm flutter build apk --debug
```

Debug APKs use `app.quickdrop.transfer.debug`. Release uses `app.quickdrop.transfer`. For a release, create your own signing keystore and an ignored `app/android/key.properties` containing `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Enter real secrets locally; do not commit them. Then run `fvm flutter build appbundle --release` or `fvm flutter build apk --release`. Inspect `build/app/outputs/` for the resulting artifacts.

Existing local-network, multicast, notification, foreground-transfer, file-provider, scoped-storage and share-intent permissions/services are retained. QuickVault adds `USE_BIOMETRIC`; the activity uses FlutterFragmentActivity and an AppCompat theme for the platform biometric prompt. New icons and Android 12 splash resources are included.

Test local discovery and receiving on real Android versions, including permission denial, notification denial, screen lock and SAF content URIs. Android can suspend QuickLink if the app is backgrounded; its HTTPS relay traffic is not integrated into the existing local-transfer foreground service. Keep QuickLink in the foreground. The vault imports separate copies and may use the file picker's cache; ordinary received files and original selected files remain outside the vault.

No Android APK or signed bundle was built in this Linux environment: no Android SDK/NDK or signing credentials were preinstalled.
