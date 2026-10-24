# Prepared cloud environment

The selected checkout is `/workspace/mailsender`. The implementation was made against the supplied archive in `/workspace/localsend-main`, then copied into the selected checkout with source-file hashes verified and its original Git metadata preserved. Files remain uncommitted and have not been pushed.

The current machine has pinned SDKs, Python backend dependencies and native Linux build prerequisites under `/workspace/toolchains`. Activate them with:

```sh
source /workspace/toolchains/activate-quickdrop.sh
cd /workspace/mailsender/app
fvm flutter pub get --enforce-lockfile
fvm flutter build linux --debug --no-pub
/workspace/toolchains/start-quickdrop-cloud.sh
```

The headless helper creates a fresh private Xvfb display and app profile, starts a session D-Bus, and configures a writable receiving location at `/workspace/quickdrop-received`. It was started against this selected checkout and its protocol-v2 information response was verified using mutual TLS and the application's certificate pin. Live processes must restart in future tasks. No public relay is started automatically.

Saved configuration draft fields:

- `network.allowed_domains`: additions `storage.googleapis.com` and `pub.dev`; the existing package-manager preset is retained.
- `install_script`: activate the prepared SDKs, perform locked Flutter dependency resolution in `/workspace/mailsender/app`, and refresh the pinned QuickLink venv dependencies.
- `start_skill`: checkout/tool activation, Linux build/start/readiness instructions, meaningful tests, separate QuickLink deployment, limitations and the instruction to use the existing isolated checkout without a worktree.

The scripts were executed in this machine; a configuration draft was confirmed saved. Saving a draft does **not** publish it, execute scripts, push source, or prove restoration in a new task. Review and save the changes in environment settings, then publish the environment if you want to retain this prepared cloud setup. Publication and a newly restored task were not tested.

Outside this cloud snapshot, follow the portable build instructions in the main README instead of relying on `/workspace/toolchains`. The project ZIP excludes SDKs, build caches, local app identities/settings and Git metadata. It was unpacked and its frozen dependency resolution was checked independently.
