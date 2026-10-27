# Stage 2 verification · Nox · 28 October 2026

- Branch `main`; Flutter/Dart only. Application ID `nz.presley.stoneandbanner`.
- `buildq` passed: analyze **#1367**, all Flutter tests **#1368**, release APK **#1366** (source unchanged after build; later edits are tests/docs only).
- APK SHA-256: `81dacd759809852eb10b6d69b37192bd1c64fb5e324cea96c595cef6639efd43`.
- Nox Waydroid `192.168.240.2:5555`: release installed; `am start -W` returned cold launch; `dumpsys activity` confirmed resumed/focused `nz.presley.stoneandbanner/.MainActivity`.
- Real Waydroid smoke: started 3-seat match, passed device, placed glowing Village and adjacent Road, observed Player 2 handoff. See `evidence/stage2-waydroid-home.png`, `stage2-waydroid-board.png`, `stage2-waydroid-handoff.png`, `stage2-waydroid-next-seat.png`.
- Waydroid's install-time dexopt hung and froze this package. Its specific compiler was terminated after verification, release then launched normally; original `pm.dexopt.install=speed-profile` was restored. No data reset or desktop usage.
- Landscape and portrait widget/golden checks cover UI sizing; frame metrics from the emulator were too sparse for a meaningful jank measurement.
- Replay data can be copied/imported; no network, external distribution or account data.
