# Pinned Flutter toolchain

Linux GPU rendering needs the upstream compositor fixes in Flutter revision
`29c22be975076d2b65a36044584893fb73261fda` (engine `ed11e55631d70d7853b831ad43b3044785c84efb`).
The pin is a prerelease upstream revision, not a moving channel. It includes
[the shader positioning fix](https://github.com/flutter/flutter/pull/196083) and
[the framebuffer blit offset fix](https://github.com/flutter/flutter/pull/196189).
Flutter 3.50.0 clips NVIDIA's shader-composited frame into a quarter of the window.

Install once, then use the wrapper from this checkout:

```sh
./tool/setup_flutter
./tool/flutterw analyze --no-fatal-infos
pueue add --escape -- ./tool/flutterw test
pueue add --escape -- ./tool/flutterw build linux --release
./tool/flutterw run -d linux
```

Setup downloads the SDK and engine artifacts into ignored `flutter/`, runs pub
get, and leaves the shared Flutter installation untouched. Subsequent builds and
local gameplay can work offline with the populated caches. The wrapper checks
`.flutter-revision`; Linux CMake also rejects an unverified SDK, including IDE
builds. Configure an IDE's Flutter SDK path to this checkout's `flutter/`.

The NVIDIA CPU fallback has been removed. Linux uses hardware-accelerated Skia;
the existing Impeller opt-out is independent of CPU rendering. Neither GPU
vendor environment variables nor software rasterization are forced.

After changing native host code or SDKs, fully stop and restart the app. Hot
reload and hot restart cannot replace an already-loaded native engine library.
See [GPU verification](GPU-RENDERING-EVIDENCE.md) for observed results and the
remaining full-suite test failures.
