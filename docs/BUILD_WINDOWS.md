# Windows build

## Install without developer tools

1. Sign in to GitHub and open [QuickDrop Windows download](https://github.com/spot0003/mailsender/actions/workflows/quickdrop_windows.yml).
2. Open the latest run for the `quickdrop-delivery` branch. If no run exists, choose **Run workflow** on that branch.
3. Wait for the build/upload steps to succeed. Under **Artifacts**, download **QuickDrop-Windows-Installer**.
4. Extract that ZIP, run `QuickDrop-Setup-Windows-x64.exe`, and follow the setup wizard.
5. Alternatively, download **QuickDrop-Windows-x64**, extract the complete ZIP to a writable folder, and run `localsend_app.exe`. Keep its DLL files and `data` folder beside it.

The source ZIP downloaded from the repository's Code button is different from these compiled artifacts. Downloads require a signed-in GitHub account. Artifacts expire after 30 days; rerun the workflow to rebuild them. These are unsigned development builds for Intel/AMD 64-bit Windows 10/11. A successful build does not replace manual testing on your PC.

This dedicated workflow uses the pinned Flutter/Rust SDKs, the hosted Windows compiler, and its Microsoft-signed redistributable DLLs. It does not need the upstream Azure signing secrets or register an unsigned MSIX helper.

## Build locally

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
