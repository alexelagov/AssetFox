# AssetFox Smoke Test

Run this after a build or on a transferred `.app`.

## Launch

1. Open `AssetFox.app`.
2. Confirm the window opens once and stays in a single scene.
3. Switch between `DuplicateFinder`, `Collect Media`, `Ingest`, and `Media Info`.

## DuplicateFinder

1. Drop or select a real folder with media files.
2. Confirm scanning starts and the progress view updates.
3. Confirm duplicate groups render in the results view.
4. Confirm quarantine and CSV export actions still work.
5. Return to the root state and run a second scan.

## Collect Media

1. Select a real Premiere FCP XML file.
2. Select a destination folder.
3. Select a search root if you want smart relink coverage.
4. Verify the defaults:
   - preserve structure off
   - skip duplicates on
   - smart relink on
   - use ffprobe on if available
   - preserve mode `base_root`
   - tail N `4`
5. Run a collection and confirm the progress bar, counters, log, and summary appear.
6. Stop an in-flight run and confirm partial outputs are left in a safe state.
7. Confirm `report.csv` is written and `missing.txt` exists when files are unresolved.

## Ingest

1. Select a real source folder and confirm recursive scan updates file, folder, and size counts.
2. Select a destination folder and confirm preflight checks update.
3. Run ingest with default settings and confirm progress, verification, and result summary update.
4. Cancel an in-flight ingest and confirm partial progress remains visible.
5. Confirm TXT/CSV/JSON reports are written when report generation is enabled.

## Media Info

1. Load one or more real media files.
2. Confirm `Inspect` shows `General`, `Video`, and `Audio` metadata sections.
3. Confirm MXF or other pro formats prefer MediaInfoLib-backed fields when the embedded library is present.
4. Switch to `Compare`, select two or more files, and confirm differences render correctly.
5. Enable `Differences only` and confirm only materially different rows remain visible.
6. Export a TXT metadata report and confirm it opens correctly.

## Transfer Check

1. Zip the app or copy the `.app` bundle from the Desktop output.
2. Move it to another Mac.
3. Confirm it opens without requiring Python.
4. If Gatekeeper prompts on first launch, use `Open Anyway`.
