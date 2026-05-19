# AssetFox Smoke Test

Run this after a local build, an internal self-contained release build, or on a transferred `.app`.

## Launch / Shell

1. Open `AssetFox.app`.
2. Confirm the app opens once and stays in a single macOS window.
3. Confirm the root UI is a sidebar, not a tab bar.
4. Switch between `Quality Check`, `Ingest`, `Duplicate Finder`, `Collect Media`, `Media Info`, and `About`.
5. Confirm shortcuts navigate correctly:
   - `Command-1`: Quality Check
   - `Command-2`: Ingest
   - `Command-3`: Duplicate Finder
   - `Command-4`: Collect Media
   - `Command-5`: Media Info
   - `Command-6`: About

## Quality Check

1. Load at least two real video exports, preferably MOV/MP4/MXF.
2. Confirm each tile shows duration, resolution, frame rate, and file size.
3. Set one export as the reference.
4. Confirm synchronized play/pause, timeline scrub, previous-frame, and next-frame controls.
5. Confirm only the reference export contributes audio when unmuted.
6. Run analysis with `ffmpeg` available and confirm findings appear for black segments, freeze segments, scene/cut issues, or a clean empty state.
7. Select a finding and confirm playback seeks to that time.
8. Export QC results to TXT when findings are present.
9. Confirm missing `ffmpeg` produces a clear runtime finding instead of a crash.

## Ingest

1. Select one source folder and confirm recursive scan updates file, folder, source count, and size totals.
2. Select multiple mixed sources, including at least one file and one folder.
3. Select a destination and confirm preflight checks update for writability and capacity.
4. Run ingest with SHA-256 verification on and confirm copied/verified/skipped/failed/mismatch counts.
5. Run ingest with SHA-256 verification off and confirm copied files are marked as copied.
6. Test existing destination conflict behavior.
7. Cancel an in-flight scan or copy and confirm partial progress remains visible.
8. Confirm reports are written when report generation is enabled:
   - `ingest-summary.txt`
   - `ingest-files.csv`
   - `ingest-report.json`

## Duplicate Finder

1. Drop or select a real folder with media files.
2. Confirm scanning starts and progress updates.
3. Confirm duplicate groups render in the results view.
4. Select a duplicate set and confirm details render.
5. Confirm quarantine moves selected files into `_DUPLICATES_QUARANTINE`.
6. Confirm Trash actions require confirmation and only affect selected duplicates.
7. Confirm CSV export still works.

## Collect Media

1. Select a real Premiere FCP XML file.
2. Select a destination folder.
3. Select a search root if smart relink coverage is needed.
4. Verify defaults:
   - preserve structure off
   - skip duplicates on
   - smart relink on
   - use ffprobe on if available
   - preserve mode `base_root`
   - tail N `4`
5. Run a collection and confirm progress, counters, log, summary, `report.csv`, and `missing.txt` behavior.
6. Select a real Premiere project (`.prproj`) file and confirm media path extraction finds expected media.
7. Run with both XML and Premiere project selected and confirm duplicated source paths merge.
8. Test unsupported Windows paths and confirm they are skipped/reported rather than crashing.
9. Test FCP XML containing non-media `file://` paths such as `.pem`, `.key`, `.env`, `.sqlite`, `.txt`, and extensionless files; confirm they are skipped with reason `unsupported media extension ignored`.
10. Test FCP XML containing supported media paths such as `.mov`, `.mxf`, `.wav`, `.png`, `.jpeg`, and `.tiff`; confirm they collect normally.
11. Run:

```bash
script/test_collect_media_xml_parser.sh
```

Confirm output:

```text
CollectMediaXMLParserSecurityTests passed
```

## Media Info

1. Load one or more real media files.
2. Confirm `Inspect` shows `General`, `Video`, and `Audio` metadata sections where applicable.
3. Confirm MXF or other professional formats prefer MediaInfoLib-backed fields when the embedded library is present.
4. Switch to `Compare`, select two or more files, and confirm differences render correctly.
5. Enable `Differences only` and confirm identical rows are hidden.
6. Export a TXT metadata report and confirm it opens correctly.

## About / Runtime

1. Open `About`.
2. Confirm Version shows `0.4.3` and Build shows `12`.
3. Confirm MediaInfoLib bundled/runtime status matches the app bundle.
4. Confirm `ffmpeg` and `ffprobe` status matches the runtime environment.
5. Confirm the Analytics card is visible.
6. Toggle `Share anonymous usage analytics` off and confirm the app remains usable.

## Transfer / Release Check

For internal self-contained builds:

1. Configure `Config/Telemetry.local.xcconfig`.
2. Ensure executable `ffmpeg` and `ffprobe` are available at `AssetFox/Vendor/FFmpeg/` or through `ASSETFOX_FFMPEG_SOURCE_DIR`.
3. Run:

```bash
./script/build_release.sh
```

4. Confirm versioned artifacts are created:

```text
dist/AssetFox-<version>-build<build>-self-contained/AssetFox.app
dist/AssetFox-<version>-build<build>-self-contained.zip
```

5. Confirm latest aliases are created:

```text
dist/AssetFox.app
dist/AssetFox-macos.zip
```

6. Move the zip to another Mac.
7. Confirm it opens without requiring Python or Xcode.
8. Confirm About runtime status and analytics setting after transfer.
9. If Gatekeeper prompts on first launch, use `Open Anyway`.
