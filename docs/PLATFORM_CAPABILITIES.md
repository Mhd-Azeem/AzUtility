# Platform capabilities

| Capability | Android | Windows |
|---|---|---|
| DNS / TCP / HTTPS | User-triggered Dart sockets / HttpClient | Same |
| Throughput | Explicit HTTPS GET / POST endpoints, 1–64 MiB cap | Same |
| LAN discovery | Selected assigned RFC1918 IPv4 /24, TCP 443, optional bounded reverse DNS | Same |
| Wi-Fi | WifiInfo; explicit location permission for private identifiers | WLAN API; OS privacy restrictions can deny access |
| CPU usage | App-process CPU; system-wide usage unsupported by public API | GetSystemTimes deltas |
| RAM / volumes / battery | ActivityManager / StatFs / battery broadcast | GlobalMemoryStatusEx / volume APIs / GetSystemPowerStatus |
| File explorer | SAF grants, MediaStore and readable selected paths | Selected accessible internal/removable drives and folders |
| Recursive scan / SHA-256 | Native provider streams or filesystem isolates | Filesystem isolates |
| Copy / move | Recursive SAF or readable-path operations | Recursive filesystem operations with conflict checks |
| Share | ACTION_SEND with URI grants; scoped cache FileProvider for paths | Native file context menu; Share/Send to where OS supports it |
| Delete / recovery | Android 11+ MediaStore system trash; confirmed permanent SAF/path deletion | Recycle Bin; OS confirmation when recovery is unavailable |
| ZIP | Streaming provider ZIP; readable-path ZIP supports passwords | Isolate ZIP creation/inspection/extraction with passwords |
| File changes | Debounced readable-folder watch; manual provider refresh | Debounced watch and incremental immediate-folder index |
| Drag / keyboard | Touch-first browser | Native file drop review; F5, Alt+Up, Ctrl+A/C/X/V, F2, Delete |
| Screen / touch | Saved manual assessment | Same, mouse or touch |
| Speaker / microphone | ToneGenerator / permission-gated three-second record and playback | Notification sound / WinMM in-memory three-second record and playback |
| Vibration / sensors | Vibrator; supported accelerometer, gyro, light, proximity, magnetic readings | Explicitly unsupported |
| Benchmarks | Bounded cancelable CPU, memory and temporary storage jobs | Same |
| Reports | Comparison, charts, PDF / JSON / CSV via save-document picker | Same via selected destination |

Metrics have available, permission-required, unsupported, temporarily-unavailable or error states. No battery wear percentage is inferred. Windows CPU frequency is nominal. Android CPU is process-specific where labeled. Battery fields depend on hardware/drivers.

TCP latency excludes DNS and measures connection to the first resolved address. HTTPS latency ends at headers. Failure percentage counts failed diagnostic attempts, including DNS/TCP failures; it is not packet-level loss or ICMP ping. Jitter is the mean absolute difference between successive successful TCP samples. LAN port-443 discovery can miss hosts. Wi-Fi scans are not performed, so scan throttling is not bypassed. Windows signal quality is a driver percentage, not dBm.

SAF scans describe granted trees only. Provider capabilities, network-backed delays, unknown sizes and read-only grants can limit operations. Provider ZIP uses the JDK ZIP implementation and cannot handle encrypted archives; readable filesystem ZIPs support passwords. MediaStore respects partial photo grants. No root, All files access, private-app data access or privacy bypass is used.

Filesystem mutations reject symlink ancestors and existing destinations. Folder moves recheck sources before removing copied entries. These safeguards cannot prevent a hostile process changing paths between checks. ZIP operations use staging, reject traversal/links, require a fresh destination and cap entries/expansion at 10,000 / 512 MiB. Cancellation/failure cleans staging. Unexpected process termination can leave an internal staging item; user destinations are never silently removed.

Monitoring runs in the foreground. Charts retain 180 points per metric. Optional persisted samples are saved at most once per minute, bounded to 10,000 rows and age retention. Records retain at most 500 per category. Large lists are virtualized; scans stop at 100,000 files. Provider thumbnails use two workers and a 128-entry Dart cache. Target physical hardware performance remains unprofiled.

Bundled OFL Noto fonts cover common Latin, Arabic, Sinhala, Tamil, Devanagari and CJK PDF text. Complex shaping and unsupported characters remain font/library limitations; JSON preserves original Unicode. Automated tests do not establish physical sensor accuracy, microphone quality, sustained battery usage or production signing.
