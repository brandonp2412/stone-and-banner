# Stage 3 verification · Nox · 28 October 2026

- Canonical Flutter project on Nox, application ID nz.presley.stoneandbanner. No Glass/desktop use.
- Flutter analyze: clean.
- Nox buildq Flutter test: #1544 passed, including seeded replay/resource invariants, advanced event transitions, touch flows and refreshed goldens. Earlier focused tests #1539 (touch) and #1542 (Stage 2 regression) passed.
- Nox buildq release APK: #1545 passed, 50,751,609 bytes, SHA-256 1e167639d5f52676470afdd95d6e22d007141064e88601e6d9d936e8f83ee8ef.
- Android package ID confirmed in android/app/build.gradle.kts.
- Nox Waydroid at 192.168.240.2:5555 is connected and booted, with adequate space. Both streaming and non-streaming adb install failed in Android's StorageManagerService.allocateBytes with PackageManagerInternal.freeStorage NullPointerException. Container restart requires root privileges unavailable in this session. **Release installation, live activity and device touch smoke remain unverified.** Do not mark Stage 3 complete until these pass.
- Only generated test/failures golden-diff artifacts were removed after the corrected golden run passed.
