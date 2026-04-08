# MediaToolkit Smoke Test

Run this after a build or on a transferred `.app`.

## Launch

1. Open `MediaToolkit.app`.
2. Confirm the window opens once and stays in a single scene.
3. Switch between the `DuplicateFinder` and `Collect Media` tabs.

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

## Transfer Check

1. Zip the app or copy the `.app` bundle from the Desktop output.
2. Move it to another Mac.
3. Confirm it opens without requiring Python.
4. If Gatekeeper prompts on first launch, use `Open Anyway`.

