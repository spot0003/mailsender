# Linux and macOS

## Linux

Install the distro's compiler and GTK/tray dependencies. On Debian/Ubuntu, with administrator privileges:

```sh
sudo apt-get update
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev libsecret-1-dev
```

Install FVM and Rust 1.97.1, then from `app/`:

```sh
fvm flutter pub get --enforce-lockfile
fvm flutter build linux --release
```

Run/distribute the full `app/build/linux/x64/release/bundle/` directory. The executable remains `localsend_app` internally, with QuickDrop branding and GTK application ID `app.quickdrop.transfer`. GUI use requires a graphical session and a working session D-Bus. The Linux CMake file allows deprecation warnings for the existing tray plugin's Ayatana API; other warning-as-error checks remain in place.

PIN-encrypted vault copies are supported; no biometric check is offered on Linux. File selection and tray integration depend on the desktop environment. Legacy distribution recipes are retained for reference and require maintainer/publisher metadata before packaging.

## macOS

Use macOS, Xcode, CocoaPods, FVM, and Rust with `aarch64-apple-darwin` or `x86_64-apple-darwin`. Select your own signing team in `app/macos/Runner.xcworkspace` and configure application-group entitlements for that team before distribution.

```sh
cd app
fvm flutter pub get --enforce-lockfile
fvm flutter build macos --release
```

QuickDrop's bundle ID is `app.quickdrop.transfer`. Local-network permission, sandboxed file access, tray/menu behavior and Touch ID must be tested on real hardware. Entitlements for network client/server and selected-file read/write are preserved. Use your own Developer ID for signing/notarization. No macOS binary was built on this Linux host.
