# AZ Utility — engineering report

Date: 2026-11-02 (Asia/Colombo).

## Delivery status

This is a working integrated application implementation, **not yet complete against every item in the full master specification**. The repository was empty; there was no existing functionality, workflow or asset to preserve. Initial GitHub metadata named `main` as the default branch. Work is on `feature/az-utility` in [Mhd-Azeem/AzUtility](https://github.com/Mhd-Azeem/AzUtility).

Both native release-mode builds and packaging succeeded. The verified application/configuration commit is `d11a50549600f784f48fb2f6df9b0989a3c45c82`; [workflow 41357394257](https://github.com/Mhd-Azeem/AzUtility/actions/runs/41357394257) completed successfully for Android and Windows. The repository's current default branch is `feature/az-utility`, which became the default when the first branch was pushed to the empty repository. No production signing or physical Android testing is claimed.

Deliverables:

- `AZUtility-v1.0.0-android-arm64-test-signed.apk` — 23,434,487 bytes; release-mode ARM64 APK signed with an Android Debug certificate.
- `AZUtility-v1.0.0-windows-x64.zip` — 15,573,891 bytes; unsigned x64 executable with its full runtime distribution.
- `AZUtility-source.zip` — source, lockfile, native runners, tests, workflows and documentation.
- `SHA256SUMS.txt` — checksums for the downloaded packages and source archive.

Downloaded APK identity, target SDK, architecture, signature and checksums were verified independently of CI. Windows PE architecture, companion files, checksum and unsigned status were verified locally. The exact delivered Windows application remained running during an eight-second hidden startup check; SQLite and MSVC/Flutter runtime libraries were loaded from its distribution. Interactive hardware and permission behavior is not covered by this startup check.

Package SHA-256 values:

```text
aab568bad79fa27206c05682500c97012a0ab4b81502242f5614a6087bf2a276  AZUtility-v1.0.0-android-arm64-test-signed.apk
115d31f10da990535889c5b1b96167704668cd83a1a16b36af3451eebf2d70ba  AZUtility-v1.0.0-windows-x64.zip
```

## Architecture and commits

One Flutter/Dart application, one Android identity (`com.az.utility`), and one Windows executable (`AZUtility.exe`). The application uses Riverpod, a go_router state-preserving shell, Material 3 with the navy/cyan design system, fl_chart, and one Drift/SQLite database. Explicit SQL migrations avoid a generated-source dependency. Native access is isolated behind a platform channel, implemented in Kotlin and C++/Win32. File and network operations have dedicated services, capability models and cancellation tokens.

The commits implement the shell and three modules, native runners, local persistence and exports, safety tests, adaptive-layout corrections, locked dependencies, and build/package workflows. The local Flutter toolchain is 3.47.9 / Dart 3.13.7. Android uses AGP 8.13.2, Gradle 8.14.3 and Kotlin 2.3.20, with Java 21 on CI.

## Implemented features

### Network Analyzer

- User-triggered DNS lookup, TCP connection timing to the first resolved address, and HTTPS header timing.
- Configurable diagnostic endpoint, repeated samples, cancellation, timeout/error evidence, bounded latency history and selectable chart ranges.
- Defined successive-sample jitter and connection failure percentage, including DNS/TCP failures. No TCP measurement is called ICMP ping or packet-level loss.
- Configurable HTTPS download/POST upload tests with byte limits, live progress, elapsed time and payload rates. No user file is uploaded. No endpoint is invented for unrestricted speed testing.
- Explicit private IPv4 interface selection for bounded /24 TCP 443 discovery, progress, stop and stored findings.
- Evidence-based troubleshooting observations and persistent session history, filtering and report exports.

### Smart File Manager

- User-selected accessible folders, parent navigation, list/grid modes, search, category filters, name/size/date sorting, file metadata and bounded image thumbnails.
- Regular-file open/copy/move, file/folder rename, create folder, multi-selection, details and confirmed permanent file deletion. Destinations are validated and existing targets are rejected.
- Read-only asynchronous recursive scans, exclusions, progress, cancellation, inaccessible-entry counts and a persisted latest index. Coverage is explicitly a selected accessible subset, not an entire volume.
- Duplicate detection by size then full streaming SHA-256 in cancelable isolates, with metadata rechecks and a review interface. No automatic deletion.
- Virtualized large-file lists, category totals, clickable donut charts and an area-proportional treemap.
- ZIP creation, inspection and extraction. Workers are cancelable; extraction rejects traversal and links, requires a fresh destination, and enforces 10,000-entry / 512 MiB declared and actual-output bounds.
- Separate Android SAF browser with persisted URI grants and document-provider browse/open/rename/create/delete actions.

### Device Doctor

- Genuine platform inventory, CPU capability distinctions, system RAM, storage volume capacity/availability and battery fields where provided.
- Windows CPU uses GetSystemTimes deltas. Android system-wide CPU is explicitly unsupported; app-process CPU is labeled separately.
- Bounded percentage history charts, configurable monitoring interval and foreground-only monitoring.
- Screen-color and touch/mouse tests, Android speaker/microphone/vibration and sensor inventory, Windows notification-sound test, and connectivity tests.
- Cancelable bounded CPU, memory and temporary-file storage benchmarks, recorded results, inventory snapshots and evidence-based usage observations. No arbitrary health score or invented battery wear percentage.

### Shared application

- Adaptive mobile bottom navigation and expandable Windows sidebar, keyboard navigation shortcuts and a native minimum window size.
- Original AZ icon, dark/light themes, accent choice, reduced motion, compact density and persistent preferences.
- SQLite schema migration from v1 to v2, history bounded to 500 records per category, independent history clearing, cached file index and local-storage error states.
- JSON, CSV and PDF exports. PDF summarizes long network sample arrays; JSON/CSV retain individual measurements. Android exports use a save-document picker.
- CI for analysis/tests/builds, Android signing-secret support, Windows runtime packaging and checksums; a version-validated tag-release workflow.

## Quality evidence

- Latest local `flutter analyze`: **no issues found**.
- Latest local automated suite: **21 passed, 0 failed**.
- Coverage includes startup/navigation, saved appearance, DNS failure and timeout, offline socket failure, endpoint validation, network calculations, transfer limits, cancellation, classification, real-file hashing/duplicates, file conflicts/rename, malicious ZIP traversal, ZIP round trip, benchmark bounds, SQLite creation/upgrades and report exports.
- Dashboard layout tests passed at 1360×900 and 390×844. Local rendered previews were visually inspected with real fonts. These are widget-test renders with native capabilities unavailable, not physical-device screenshots.
- Hosted Linux and Windows each passed static analysis and all 21 automated tests, then built and packaged the application successfully. APK validation confirms only `arm64-v8a`, package `com.az.utility`, version `1.0.0`, minimum SDK 24 and target SDK 36. APK Signature Scheme v2 verification passed; the signer is `CN=Android Debug, O=Android, C=US`.
- Integration test source is provided, but has not been executed against a physical Android device or a packaged Windows application.

No device performance profiling, sustained battery measurement, physical audio-quality test or Android permission behavior is claimed as verified. The PDF library's built-in font has limited Unicode coverage; JSON preserves original text.

## Build and signing constraints

Local Flutter/Dart were installed into the workspace and used for testing. `flutter doctor -v` confirms that this machine lacks Android command-line tools and Visual Studio C++ build tools. GitHub Actions supplies the native toolchains.

Android CI produces a release-mode ARM64 APK. Without `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD` and `ANDROID_KEY_ALIAS`, the APK uses a debug certificate and must be labeled `test-signed`. It is test-installable, not a production-signed release.

Windows packaging keeps the executable, Flutter and plugin/native libraries, assets, ICU data, AOT library and available MSVC redistributable DLLs together. The executable is unsigned. A bare EXE is not a valid distribution.

No GitHub release tag has been pushed and no public production release has been published.

## Installation

Android: download the ARM64 APK, permit installation from the chosen source, install AZ Utility, and grant a selected folder only when requested. Microphone permission is used only for the recording test. No root, administrator, location or All files permission is requested.

Windows: extract the entire distribution ZIP into a user-writable folder and launch `AZUtility.exe`, keeping all companion files together. Select a readable folder/drive before scanning. Deletions are permanent and require confirmation.

For local source builds, see the exact commands and prerequisites in the repository README.

## Outstanding implementation and verification

1. Physical Android 15 testing and interactive packaged Windows testing remain required. Production Android signing and optional Windows signing require real keys/certificates. A production release has not been published.
2. Android MediaStore integration and provider-native recursive scan, hashing, duplicate analysis, ZIP, copy/move/share are not implemented. SAF currently provides browsing and basic document actions; Dart analysis needs readable filesystem paths.
3. Recursive folder copy/move, native sharing, recycle/trash integration, drag-and-drop, incremental filesystem watching, folder-size rankings and richer duplicate multi-selection remain unfinished. Regular-file actions work; deletion is explicitly permanent.
4. Wi-Fi SSID/BSSID permission acquisition and a dedicated Wi-Fi screen are unfinished. Android reports available link data and marks private identifiers permission-required. Windows WLAN-specific metrics and LAN hostname resolution are unfinished.
5. Live sensor streams, Windows microphone recording, persisted continuous monitoring samples, detailed metric subpages and recorded manual screen/touch outcomes remain unfinished. Unsupported hardware capabilities are stated explicitly.
6. History comparisons, configurable age-based retention, reset-settings controls, full Unicode PDF fonts and some advanced report visualizations remain unfinished. Current retention is a fixed per-category record cap.

Continuation priority: test permissions and real file operations on Android 15, exercise the packaged Windows interactions, then extend Android provider-backed file operations and native file safety/UX before broadening advanced diagnostics. Preserve the existing working service boundaries and safety tests.
