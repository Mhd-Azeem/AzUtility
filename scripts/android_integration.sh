#!/usr/bin/env bash
# Keep this in one shell: emulator-runner executes separate script lines separately.
set -u
adb logcat -c
result=0
timeout 12m flutter test integration_test/provider_test.dart -d emulator-5554 --timeout 3m --verbose > integration.log 2>&1 || result=$?
cat integration.log
adb logcat -d > android-logcat.txt
if [ "$result" -ne 0 ]; then tail -n 250 android-logcat.txt; fi
exit "$result"
