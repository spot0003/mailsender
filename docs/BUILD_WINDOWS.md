# Windows build

Use Windows with Visual Studio 2022's **Desktop development with C++**, the Windows SDK, Git, FVM and the MSVC Rust toolchain. This cannot be built or signed by the Linux cloud machine.

From the project root in PowerShell:

```powershell
fvm install
rustup toolchain install 1.97.1 --profile minimal
rustup target add --toolchain 1.97.1 x86_64-pc-windows-msvc
Set-Location app
fvm flutter pub get --enforce-lockfile
fvm flutter analyze
fvm flutter test
fvm flutter build windows --release
```

The portable bundle is `app/build/windows/x64/runner/Release/`. Distribute the **whole directory**, including DLLs, `data/`, and the Rust library; the executable's internal name remains `localsend_app.exe`, its displayed name and icon are QuickDrop. Test on a clean Windows machine with the Visual C++ redistributable installed. Permit the configured TCP/UDP transfer port on private networks only (default 53317); multicast may be blocked on public/guest Wi-Fi.

Vault PIN encryption is available; native biometric-only authentication is not exposed on Windows because Windows Hello does not guarantee a biometric-only check. Save dialogs, Explorer integration and tray behavior need real-machine acceptance tests.

The updated Inno/MSIX source uses a distinct QuickDrop installer/package identity, and retains the executable filename expected by native integration. Configure **your own publisher, URLs, certificates and store registration** before using these optional release helpers. Do not reuse upstream signing keys or publish as LocalSend. Only portable build commands above are the baseline workflow; the installer/MSIX pipeline was not executed here.
