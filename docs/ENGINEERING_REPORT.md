# AZ Utility — engineering report

Date: 2026-11-02 (Asia/Colombo).

Master-scope implementation and packaged test delivery are complete within the available environment. Physical-device validation and production signing remain external requirements, detailed below.

## Repository and architecture

Repository: [Mhd-Azeem/AzUtility](https://github.com/Mhd-Azeem/AzUtility). Branch/default branch: `feature/az-utility`. The initially empty repository was implemented without replacing unrelated work. One Flutter application contains Network Analyzer, Smart File Manager and Device Doctor, one Android identity (`com.az.utility`) and one Windows executable (`AZUtility.exe`).

Flutter 3.47.9 / Dart 3.13.7, Riverpod, go_router, Material 3, fl_chart and Drift/SQLite. Kotlin handles Android APIs, C++/Win32 handles Windows APIs. Network/file/device services separate operations from UI. SQLite uses explicit schema-v3 creation/upgrades; no generated source is required. Dependencies/lockfile, native projects, source, tests, OFL font licenses and workflows are committed.

The implementation expanded the original foundation with provider-native Android storage, MediaStore, Windows WLAN/microphone/recycle/share/drop adapters, recursive folder operations, safe encrypted filesystem ZIPs, live Android sensors, detailed device cards, monitoring persistence, report comparisons and retention. See [scope mapping](ACCEPTANCE.md) and [capabilities](PLATFORM_CAPABILITIES.md).

## Implemented features

### Network Analyzer

Real DNS, first-address TCP connection timing and HTTPS header timing; timeouts, cancellation and categorized error evidence. Bounded latency chart/sample counts, successive-sample jitter and explicit diagnostic-failure estimates. Configured authorized HTTPS download/POST upload endpoints, byte caps, live progress, Mbps and MB/s, history. Wi-Fi details and optional location permission for private Android identifiers; Windows WLAN metrics. Explicit private-interface /24 TCP 443 discovery with bounded concurrency, stop and hostname lookup. Evidence-based troubleshooting, date filtering, two-record numeric/chart comparison and JSON/CSV/PDF exports. No packet-level loss or ISP fault claim is invented.

### Smart File Manager

Real selected-path and Android SAF/MediaStore browsing; list/grid/search/sort/breadcrumbs, thumbnails and metadata, multiple selection, native open/share, folder creation/rename, recursive copy/move with conflicts and source checks. Windows Recycle Bin and Android supported-media system trash; confirmed permanent provider/path deletion where recovery is unavailable. Windows file-drop review, clipboard shortcuts and native menus.

Read-only recursive worker scans with progress/cancellation/exclusions/errors/coverage, persistent cache and incremental immediate-folder path updates. Full SHA-256 duplicates with metadata checks and reviewed selection. Virtualized large-file filters/preview/removal. Clickable category donut/bars/treemap and direct-folder size rankings. ZIP creation from files/folders including empty folders, inspect/extract, progress/cancel, staging cleanup, no overwrite, traversal/link rejection and 10,000-entry / 512 MiB bounds. Passwords are ephemeral and supported for filesystem ZIPs; provider ZIP is unencrypted streaming JDK ZIP.

Android DocumentEngine streams real granted provider URIs for recursive scan/hash/duplicate/copy/move/ZIP. Unknown provider sizes remain unavailable. MediaStore supports partial photo grants and system trash. Native thumbnails use a bounded worker pool/cache. No All files/root/private-app storage bypass.

### Device Doctor

Four real capability-aware CPU/RAM/storage/battery cards with details and bounded history; hardware, adapter and supported sensor inventory. Windows system CPU; separately labeled Android process CPU. Configurable foreground refresh, optional persisted monitoring, lifecycle cancellation. Saved manual screen/touch assessments, speaker/microphone tests, Android vibration and live supported sensor readings. Windows microphone records in memory for three seconds and plays back locally.

Conservative configurable CPU, memory and temporary-storage benchmarks with validation, progress/cancel, detailed results and local comparison. Health findings use transparent current-usage evidence with Good / Attention / Warning / Not assessed categories. No arbitrary score or invented wear percentage.

### Shared application

Responsive navy/cyan design with original AZ icon, mobile navigation/desktop sidebar, theme/accent/density/reduced motion, operational dashboard, skeletons/error/empty states. One local database stores preferences, bounded categorized history, index and opt-in monitoring. Configurable age retention and 500-record/category cap; monitoring at most once/minute, 10,000 rows, 180-point live charts. Independent clearing and reset preferences. Lazy history loading, filtering, comparison and local PDF/JSON/CSV exports. OFL Noto fonts are bundled for common Latin/Arabic/Sinhala/Tamil/Devanagari/CJK PDF text.

## Quality evidence

Local automated suite: **31 passed, 0 failed**. Covers startup/navigation/appearance persistence, offline/DNS/timeout errors, measurement math, endpoint/transfer bounds, classification/hash/duplicates, recursive copy/move/conflicts/containment, incremental index, encrypted ZIP wrong password/roundtrip/folder/empty directory/traversal/cancel cleanup, benchmark bounds, migrations/retention/reset/monitoring, CSV/JSON/multilingual PDF and 390/1360 layouts. Static analysis: **no issues found**. Hosted Linux and Windows both passed all 31 tests and static analysis.

Native Windows integration launches the real debug runner, reads native RAM/architecture and navigates to Device Doctor. Local interface inspection of the downloaded release also verified live system readings, Device Doctor navigation/CPU detail chart and native-picker browsing of three real test files. It did not assess all destructive actions or every hardware test. Android 15 emulator integration exercises native snapshots and a debug-only DocumentsProvider fixture: recursive scan, SHA-256 duplicates, copy conflict, ZIP roundtrip, traversal rejection and staging cleanup. The fixture provider is absent from release manifests. Its debug declaration follows the system-required exported/MANAGE_DOCUMENTS protection contract ([Android framework source](https://android.googlesource.com/platform/frameworks/base/+/HEAD/core/java/android/provider/DocumentsProvider.java)).

## Build evidence

Verified code commit: `7cf1415b6cb578afd13cd35b700bebda9f3ac99a`. [CI run 41392198849](https://github.com/Mhd-Azeem/AzUtility/actions/runs/41392198849) succeeded for both Android and Windows. Windows native startup/snapshot/navigation integration passed before the release build. Later commits refine the debug fixture/test harness and documentation; delivered release runtime source is unchanged. [Latest CI run 41394822788](https://github.com/Mhd-Azeem/AzUtility/actions/runs/41394822788) also passed both platform jobs at `c8453437` including all 31 tests and native Windows integration.

Downloaded artifacts were checked against GitHub artifact SHA-256 digests. Independent APK parsing verified package/name/version, only ARM64 libraries, minimum SDK 24, target SDK 36 and absence of the debug fixture provider. APK Signature Scheme v2 verifies with signer `C=US, O=Android, CN=Android Debug`. Windows PE machine is AMD64; all required Flutter/SQLite/MSVC/runtime files are present, and Authenticode reports NotSigned. The downloaded release executable remained running through an eight-second hidden startup check; only that owned smoke-test process was stopped.

| Deliverable | Bytes | SHA-256 |
|---|---:|---|
| AZUtility-v1.0.0-android-arm64-test-signed.apk | 38,897,247 | `fd261b13be613276a74fc2ebf3f57a491265b33e0dea0649d990cd4cd09e8fe5` |
| AZUtility-v1.0.0-windows-x64.zip | 30,353,704 | `d83867abc8d50300b5a1ddc5728d632f4d7031d998195f8bcc48d1d9a3b43895` |

Source, report, scope/capability records, updated widget-render previews and checksums accompany the packages. Previews are widget-test renders with native capabilities unavailable, not physical-device screenshots. Source archive contains the committed source/lockfile/native projects/tests/workflows/assets/licenses; Flutter/SDK/dependency installation remains required to rebuild.

**Android 15 emulator integration passed** at `c8453437`: [run 41394822781](https://github.com/Mhd-Azeem/AzUtility/actions/runs/41394822781). The real x86_64 Android 15 debug runner completed native startup and the authorized document-provider round trip, including scan/hash/duplicates, copy conflicts, ZIP extraction, traversal rejection and cleanup. This is emulator evidence, not physical ARM64 hardware validation. The ARM64 release package is independently built/validated as above.

## Installation and signing

Android: install the ARM64 APK, allow installation from the chosen source, then open AZ Utility. Grant selected SAF/media/microphone/optional Wi-Fi location access only when using those features. The `test-signed` APK is release-mode signed with an Android Debug certificate, not production-signed. Test certificates can differ between hosted runners: Android can reject updates over an earlier test install. Export needed local history before uninstalling an earlier test copy. Production requires `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`.

Windows: extract the entire ZIP into a user-writable folder and run `AZUtility.exe`, retaining all DLLs and `data/`. It is unsigned; routine use does not need administrator privileges. Packaging includes Flutter, SQLite/plugin assets, ICU/AOT and MSVC runtime dependencies. A bare EXE is not a valid distribution.

No release tag/public production release has been published. The tag workflow is configured. Local Android/Visual Studio build toolchains are absent, so hosted native toolchains produce the packages.

## Remaining external verification and limitations

Physical Android 15 testing is unavailable: no claim of real sensor accuracy, microphone/speaker quality, vibration, permission UX, provider/device diversity, thermal behavior or sustained battery measurement. Interactive Windows driver/device/provider testing and target-hardware performance profiling remain required. Production Android signing and optional Windows code signing require real credentials; none were fabricated.

Android system-wide CPU is unavailable through the supported public API. Windows sensor/vibration and unsupported battery fields are labeled. Provider encrypted ZIP is unsupported; filesystem ZIP supports passwords. Wi-Fi privacy/driver support varies. TCP-443 LAN discovery can miss devices. Folder rankings are immediate indexed child groups. Symlink checks cannot eliminate a hostile concurrent path-replacement race. PDF complex shaping/glyph coverage remains subject to font/library limits; JSON preserves Unicode. See PLATFORM_CAPABILITIES.md for precise limits.
