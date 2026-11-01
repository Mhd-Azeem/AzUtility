# AZ Utility implementation record

Repository audit: the remote repository was empty on 2026-11-02. GitHub reports default branch `main`; there are no commits, workflows, dependencies, contribution rules, or assets to preserve. Implementation branch: `feature/az-utility`.

One Flutter application, `com.az.utility`, with shared adaptive navigation, persistence, capability-aware native adapters, and independent network, files, and device services. Work proceeds through functional slices, automated verification, native build verification, and packaging. Unsupported platform capabilities are reported explicitly. No synthetic production measurements.

Required safety boundaries: explicit local scan roots, no automatic deletion, no automatic LAN probing, bounded transfer/benchmark sizes, no symlink traversal, no archive overwrite, and local-only history.

Build evidence and remaining restrictions will be recorded in `docs/ENGINEERING_REPORT.md` after verification.
