# Platform capabilities

| Capability | Android | Windows |
|---|---|---|
| TCP / DNS / HTTPS diagnostics | Dart sockets and HttpClient | Dart sockets and HttpClient |
| Throughput | Configured HTTPS GET / POST, 1–64 MiB cap | Same |
| LAN discovery | Explicit assigned RFC1918 IPv4 /24, TCP 443 | Same |
| System CPU usage | Unsupported by public API; process CPU shown separately | GetSystemTimes deltas |
| System RAM | ActivityManager.MemoryInfo | GlobalMemoryStatusEx |
| Storage volume | StatFs for app's volume | GetLogicalDriveStrings / GetDiskFreeSpaceEx |
| Battery | Android battery broadcast fields | GetSystemPowerStatus; no temperature/wear |
| Inventory | Build, display, network, sensor inventory | Registry processor/BIOS fields, display, adapters |
| Filesystem browser / scanning | Only readable selected paths | Selected accessible folders/drives |
| Document providers | SAF tree grants; browse/open/rename/create/delete documents | Not applicable |
| Duplicate analysis | Readable filesystem paths, full SHA-256 | Same |
| Archives | Readable filesystem paths; background isolates | Same |
| Screen/touch | Flutter interactive test | Flutter interactive test with mouse/touch |
| Speaker | ToneGenerator | Windows notification sound |
| Microphone | Three-second local record/playback, permission required | Explicitly unsupported by current adapter |
| Vibration | Native vibrator if present | Unsupported |
| Sensors | Native inventory | Unsupported |
| PDF / JSON / CSV | Android save-document picker | Selected filesystem destination |

The absence of a TCP 443 response does not prove a host is absent. Android SSID/BSSID require additional permission handling and are marked permission-required without requesting location. No battery health percentage is inferred. CPU clock on Windows is the registry nominal value, not a live frequency.

SAF browsing does not imply that provider documents can be hashed, recursively scanned or archived through Dart filesystem APIs. Those analysis operations currently require a readable filesystem path. MediaStore categorization, provider-native copy/move/share/scan/hash and real-time sensor values remain additional work.

Filesystem mutations reject symlink ancestors and existing destinations. Checks are intended for normal local use, not protection against another process deliberately replacing paths between checks. Deletion is permanent and requires confirmation; the app does not yet integrate with Windows Recycle Bin or provider trash. Interrupted archive extraction may leave files in its newly created destination; user review is required before removing partial output.

Native adapters have not yet been exercised on physical Android hardware. Automated Flutter tests mock the absence of a native adapter and test real temporary local files; those tests do not validate sensor accuracy, audibility, touch hardware or permission behavior on a device.
