# AZ Utility

One offline-first Flutter application for Android and Windows, combining Network Analyzer, Smart File Manager and Device Doctor. Android identity: `com.az.utility`; Windows executable: `AZUtility.exe`.

## Develop

Use Flutter **3.47.9** (stable), Java 21, the Android SDK, and Visual Studio 2022/2026 with Desktop development with C++ for Windows. Dependency versions are pinned in `pubspec.yaml`; commit `pubspec.lock` after dependency resolution. SQLite uses sqlite3's native build hook. Drift uses explicit SQL migrations, so no generated source is required.

```sh
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
flutter build windows --release
```

The application has no account, backend, advertising or analytics dependency. Initial network endpoint is `https://example.com`; tests run only after user action. Speed tests require an authorized HTTPS endpoint configured in Settings, and never send user file contents.

## Install

Android: use an ARM64 APK, allow installation from your selected source, and open AZ Utility. The unsigned-production fallback is **debug certificate signed**, with `test-signed` in the artifact filename. Production signing requires the four `ANDROID_*` secrets used by the workflows. Never distribute the fallback as a production-signed release.

Windows: extract the entire distribution ZIP into a user-writable folder, keeping `data/`, all DLLs, and `AZUtility.exe` together. Run `AZUtility.exe`. The executable is unsigned. Administrator privileges are not required for routine use.

## Data and permissions

One local SQLite database stores settings, bounded diagnostic history and the latest file index. Each history category can be cleared in Settings. Android uses a folder picker and persistable SAF URI grants; microphone access is requested only for the recording test. No root, All files access or location permission is requested. Files accessible to a document provider are browsed separately from readable filesystem paths. Other apps' private data is inaccessible.

Network latency means TCP connection time or HTTPS header time as labeled, never ICMP ping. Failure estimates are failed TCP connection attempts, not packet-level loss. LAN discovery requires explicit private-interface selection and probes only TCP port 443 in a /24; devices without that service may be missed.

File scans do not follow symlinks and stop at 100,000 indexed files. Duplicate groups use full SHA-256 with before/after metadata checks. File deletion is explicit, confirmed and permanent; there is no recovery guarantee. ZIP extraction rejects traversal and links, refuses an existing destination and caps expansion at 512 MiB / 10,000 entries. Cancellation can leave a partially extracted folder.

## Build automation

`ci.yml` verifies and packages on pushes and pull requests. `release.yml` validates version tags, builds both targets and attaches checksums and signing notices. Workflows must finish successfully before artifacts can be considered verified. See `docs/ENGINEERING_REPORT.md` for actual evidence and outstanding work.
