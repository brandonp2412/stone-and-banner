# GPU rendering fix — 16 November 2026

The automatic NVIDIA CPU workaround from `8b9c698` is removed. The project pins
Flutter `29c22be975076d2b65a36044584893fb73261fda`, engine
`ed11e55631d70d7853b831ad43b3044785c84efb`, content hash
`9d33e70b812840955239dc7707816ff321cd21b2`. This is an upstream prerelease revision
containing [the NVIDIA shader positioning correction (#196083)](https://github.com/flutter/flutter/pull/196083)
and [the blit offset correction (#196189)](https://github.com/flutter/flutter/pull/196189).
No engine binary patch, driver change, GPU-vendor override or CPU default is used.
The existing Linux Impeller opt-out selects GPU Skia, not software rasterization.

`tool/setup_flutter` installs a project-local SDK without modifying the shared
SDK. `tool/flutterw` verifies the revision; Linux CMake rejects other revisions.
Both Linux configurations built with this guard (#6128); an isolated CMake
configure using the old shared SDK was rejected with the expected diagnostic
(`evidence/desktop/gpu/old-sdk-rejected.txt`). See [setup](TOOLCHAIN.md).

## GPU proof

All files below are under `evidence/desktop/gpu/`. Tests used an isolated native
Wayland Cage compositor on this host's **RTX 4090, NVIDIA 620.70.06**, with
`WLR_BACKENDS=headless WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128`.
Unlike Xvfb or a pixman renderer, this compositor uses NVIDIA's actual EGL/GLES
implementation. Logs identify `NVIDIA Corporation` and `NVIDIA GeForce RTX
4090/PCIe/SSE2` (`baseline-driver.txt`). No shared desktop window was created.

1. **Reproduce:** The old release with OpenGL enabled displayed the same clipped,
   mostly black frame at 1920×1080 (#6115, `before-gpu-1920.png`). Its game process
   appears as type **G** in `nvidia-smi pmon` (`before-gpu-processes.txt`).
2. **Debug:** The pinned SDK's debug build rendered Home correctly at 1920×1080
   and after live resize to 1280×720 (#6122, `fixed-debug-home-1920.png`,
   `fixed-debug-home-resized-1280.png`). `debug-gpu-proof.json` records the game
   PID, NVIDIA graphics-process row, loaded NVIDIA libraries, engine-library
   SHA-256, and the absence of software-rendering environment overrides.
3. **Release:** The pinned release rendered Home, setup and the board correctly
   at 1920×1080 (#6126). Through real virtual-pointer input on the isolated
   compositor, New local match → Start match → private handoff → legal Village
   placement gave Player 1 **1 VP** and changed the phase to Road. Screenshots:
   `fixed-release-home-1920.png`, `fixed-release-setup-1920.png`,
   `fixed-release-board-1920.png`, `fixed-release-village-1920.png`.
4. **Resize and continue:** The same running release match resized to 1280×720
   and back to 1920×1080 with its Village and score preserved, then accepted a
   legal Road and handed off to Player 2. Screenshots:
   `fixed-release-match-resized-1280.png`,
   `fixed-release-match-restored-1920.png`, `fixed-release-road-handoff.png`.
5. **Actual GPU, not a CPU fallback:** `release-gpu-proof.json` records game PID
   485330 as a type **G** NVIDIA process, loaded NVIDIA EGL/graphics libraries,
   and null values for `FLUTTER_LINUX_RENDERER`, `LIBGL_ALWAYS_SOFTWARE` and
   `MESA_LOADER_DRIVER_OVERRIDE`. The compositor log and game-process evidence
   are separate checks; a GPU compositor alone would not establish game GPU use.

Screenshots were captured using native Wayland `grim` after frames settled and
visually inspected. Capture hashes, dimensions and near-black pixel fractions
are in `captures.json`; those measurements supplement visual inspection.
This verifies rendering, resize and a setup interaction. It is not a long-game
performance or frame-pacing benchmark.

## Builds and remaining checks

- Pinned SDK bootstrap succeeded (#6110). Shared SDK unchanged.
- Analyzer ran with no errors/warnings and existing Material import deprecation
  infos; `--no-fatal-infos` was used (#6112).
- Desktop regression passed independently (#6124).
- Full suite was run: **151 passed, 83 failed** (#6112 test log), with existing
  font-change callbacks left pending after widget disposal. The combined build
  task continued after the test failure; its successful task result is not a
  claim that the full suite passed.
- Linux debug/release built (#6112 and #6128). Android release APK built using
  the pinned SDK (#6121), installed and cold-launched on isolated read-only AVD
  `stone_design_api35`, serial `emulator-5584`, 1920×1080 / 160 dpi. Home was
  inspected (`pinned-sdk-android-home.png`); AndroidRuntime/Flutter error-log
  check returned no lines. No physical-device test.
- Test compositor and emulator were closed. Original user app processes were
  left alone. No public release or unrelated machine was used.

The pin is deliberately immutable but currently prerelease: updating to a fixed
stable SDK later requires the same GPU regression checks. A full process restart
is required to load the new native engine; hot reload cannot replace it.
