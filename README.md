# AZ Utility

One offline-first Flutter application for Android and Windows, combining Network Analyzer, Smart File Manager and Device Doctor. Android identity: `com.az.utility`; Windows executable: `AZUtility.exe`.

## Develop

Use Flutter **3.47.9**, Java 21, Android SDK, and Visual Studio with Desktop development with C++ for Windows. Dependencies and lockfile are committed. Drift uses explicit SQL migrations; no generated source is required.

```sh
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
flutter build windows --release
```

No account, backend, advertising or analytics dependency. Initial diagnostic endpoint: `https://example.com`; network tests require user action. Speed tests require explicitly configured authorized HTTPS endpoints and never send user file contents.

## Install

Android: install the ARM64 APK after allowing installation from the chosen source. The `test-signed` package is release-mode with an Android Debug certificate. Production signing requires the four `ANDROID_*` secrets in the workflows.

Windows: extract the entire distribution ZIP into a user-writable folder, keeping `data/`, all DLLs and `AZUtility.exe` together. Run `AZUtility.exe`. It is unsigned. Routine use does not require administrator privileges.

## Features and permissions

Real DNS/TCP/HTTPS diagnostics, configured throughput tests, Wi-Fi details, private LAN discovery, local history, comparisons and export. Latency and failure estimates have explicit methodologies; TCP timing is never called ICMP ping.

Files include recursive folder operations, SAF/MediaStore integration, full SHA-256 duplicates, large-file review, interactive storage charts, incremental readable-folder indexing and ZIP operations. Windows uses the Recycle Bin; Android media uses system trash where supported. SAF/path deletion is confirmed and permanent. Archive traversal/links/overwrite are rejected, with 10,000-entry / 512 MiB bounds and staging cleanup. Readable-path ZIPs support passwords; provider ZIPs do not.

Device features include capability-aware inventory, four detailed metric cards, foreground monitoring, supported live sensors, interactive hardware checks, conservative benchmarks and evidence-based observations. Monitoring persistence is optional and bounded.

One SQLite database stores preferences, history and the latest index, with schema migrations and configurable retention. Clear each category independently in Settings. PDF/JSON/CSV export works locally; PDF fonts are bundled.

Android requests SAF grants, media, microphone and optional Wi-Fi location permissions at feature use with explanations. No root or All files access; other apps' private data remains inaccessible. See [platform capabilities](docs/PLATFORM_CAPABILITIES.md) for exact restrictions.

## Automation and evidence

`ci.yml` checks source/tests, runs native Windows startup/navigation and packages both platforms. `android-integration.yml` exercises provider operations on Android 15 using a debug-only fixture. `release.yml` builds and attaches validated artifacts/checksums when a valid version tag is pushed. See [engineering report](docs/ENGINEERING_REPORT.md) for actual results, signing status and remaining external verification.
