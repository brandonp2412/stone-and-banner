# Screenshot evidence

The dated directories here contain historical QA captures and logs. Their images record the app as it appeared during those sessions.

Current product screenshots live in [Fastlane screenshots](../../fastlane/metadata/android/en-US/images/) and are displayed in the [project README](../../README.md). Regenerate those images with `tool/capture_readme_screenshots.py`; it captures the current app and checks its visible text for retired terminology.

Visual regression baselines live in `test/goldens/` and `tool/visual_snapshots/`. Refresh them from their Flutter tests when the intended UI changes, then review the generated images before committing them.
