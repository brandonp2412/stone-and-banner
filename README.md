# Stone & Banner

An original, offline-first, turn-based Android strategy game in Kotlin and Jetpack Compose Material 3. The \`engine\` module is plain JVM Kotlin: game transitions are immutable and deterministic, with no Android, UI or network imports.

Stage 1 is a **compiling prototype**, not a playable match. It contains Home / Board / Rules navigation, a seeded 19-hex board preview, a functioning preview turn counter, basic deterministic rules operations, and JVM tests. See [docs/ROADMAP.md](docs/ROADMAP.md) for the eight-stage plan and acceptance criteria, [docs/RULES.md](docs/RULES.md) for the proposed standalone rules, and [docs/IP.md](docs/IP.md) for publication restrictions.

## Build

- Java 17, Android SDK 37, Gradle 9.8.1, Android Gradle Plugin 9.4.1, Kotlin 2.4.20.
- \`buildq --wait -- ./gradlew :engine:test :app:assembleRelease\` on Glass.
- Local trial release APK: \`app/build/outputs/apk/release/app-release.apk\`.
- The release is **only for local device testing**. The project defaults to debug signing; Glass may override it with its locally managed signing policy. Do not distribute it.
- No network, account or analytics permissions.

All runtime random outcomes in future stages must be represented as explicit, replayable events. A seeded setup generator must save its seed and resulting layout. UI reads state and dispatches actions; it never decides legality.

No CATAN artwork, rule text, trademarks or lore belong in the product.
