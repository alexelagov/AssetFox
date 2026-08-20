# assetfox-cli

Headless companion to the AssetFox app. It reuses the app's inspection and
quality-check engines (`MediaInfoInspector`, `MediaInfoLibService`,
`QualityCheckAnalyzer`) so command-line runs and app runs report the same
values from the same code.

Primary consumer: the PM Studio deliverables-check service, which shells out
to this binary and parses the JSON contract below.

## Build

Requires macOS 15+ and a Swift 6 toolchain (Command Line Tools are enough,
full Xcode is not needed):

```bash
swift build -c release
.build/release/assetfox-cli doctor --pretty
```

The MediaInfoLib dylib is bundled as an SPM resource
(`AssetFox_AssetFoxCLI.bundle`), which `swift build` places next to the
binary. When relocating the binary, keep the bundle beside it, or point
`ASSETFOX_MEDIAINFO_DYLIB` at a `libmediainfo` dylib. ffmpeg/ffprobe resolve
from the app's usual candidates (bundled `Tools/`, `/opt/homebrew/bin`,
`/usr/local/bin`).

The package compiles a curated subset of app sources plus a CLI-only
`MediaInfoLibBridge` shim (`cli/Sources/MediaInfoLibBridgeShim.swift`) that
dlopens the dylib instead of link-time binding. Never add that shim to the
app target - the app keeps its Objective-C++ bridge.

## Conventions

- Exactly one JSON object on stdout; progress and errors go to stderr.
- Exit codes: `0` success (per-file problems are reported inside the JSON),
  `2` usage error, `1` unexpected failure.
- Every payload carries `schema` (`assetfox.cli/v1`), `cli_version`,
  and `command`.
- Keys are `snake_case`; absent values are omitted, never `null`.
- `--pretty` pretty-prints; default output is compact with sorted keys.

## `inspect` - file passports

```bash
assetfox-cli inspect [--pretty] <file>...
```

Returns `files`, one passport per input, in input order. A passport has three
layers with different trust levels:

| Layer | Source | Use for |
| --- | --- | --- |
| `av` | AVFoundation | numeric comparison: `duration_seconds`, `width`, `height`, `nominal_frame_rate` |
| `summary` | merged MediaInfoLib -> AVFoundation -> ImageIO -> ffprobe | display strings; `metadata_source` names the winning chain |
| `media_info` | MediaInfoLib complete dump (when the dylib loads) | exact codec/profile matching: `general`, `video_tracks[]`, `audio_tracks[]` |
| `ffprobe` | ffprobe, primary video stream only | measured pixel format: `pix_fmt`, derived `video_bit_depth` |

Since 0.2.0 the `media_info` payload also carries the encoding settings the
delivery checker's machine rules read, as machine types rather than display
strings: `general.is_streamable` (bool - MP4 `moov` atom before the media
data, i.e. "faststart"), and per video track `format_settings_cabac` (bool),
`format_settings_ref_frames` (int), `format_settings_gop` (raw MediaInfo
spelling, e.g. `"M=4, N=24"`). Every field is omitted where MediaInfo does
not answer - absence means "could not verify", never "no".

The `ffprobe` layer exists because MediaInfo does not report bit depth for
ProRes QuickTime files, and the AVFoundation depth in `summary` is bits per
pixel (24 for 8-bit), which no bit-depth rule may trust. `pix_fmt` is
ffprobe's decoded pixel format verbatim; `video_bit_depth` (int, bits per
channel) is derived from the depth token in that name (`yuv422p10le` -> 10,
`yuv420p` -> 8), and `video_bit_depth_source` names the derivation
(`"pix_fmt"`). The derivation only reads name families where the trailing
token really is a per-channel depth (planar YUV/RGB, grayscale); packed
formats like `nv12` or `rgb24` yield no `video_bit_depth` at all. The whole
layer is omitted when ffprobe is unavailable or reported no pixel format -
as everywhere in the passport, absence means "could not verify".

Unreadable inputs produce `{path, file_name, error}` instead. Per-file
`warnings[]`/`errors[]` surface degraded metadata sources.

`media_info` values are MediaInfo display strings (for example
`format: "ProRes"`, `format_profile: "422 HQ"`, `frame_rate:
"29.970 (30000/1001) FPS"`, `chroma_subsampling: "4:2:2"`). Consumers should
match on them verbatim rather than re-deriving numbers from them; numeric
checks belong to `av`.

## `qc` - quality findings

```bash
assetfox-cli qc [--reference <file>] [--tolerance-frames N] [--include-raw] [--pretty] <file>...
```

Runs the app's ffmpeg analysis (blackdetect, freezedetect, scene-cut
comparison against the reference). `--tolerance-frames` defaults to 2, same
as the app. The reference file is added to the run automatically and marked
`is_reference` in `files`.

Payload: `files[]` (with the loaded timing metadata), `findings[]`,
`measurements[]`, and optionally `missing_files[]`, `warnings[]`,
`raw_outputs[]` (with `--include-raw`).

A finding:

```json
{
  "severity": "info | warning | critical",
  "kind": "black_frame | freeze_frame | cut_mismatch | runtime",
  "file_name": "broken.mp4",
  "time_seconds": 3.0,
  "duration_seconds": 1.2,
  "message": "Black segment detected",
  "details": "blackdetect: start 3.0, duration 1.2"
}
```

`kind: "runtime"` with `severity: "critical"` means ffmpeg itself was
unavailable - treat the run as not performed rather than as a clean file.

A measurement - what the file *is*, for a caller holding a delivery spec to
compare against. Findings are events; these are facts:

```json
{
  "file_name": "social_cut.mp4",
  "content_bounds": { "x": 656, "y": 0, "width": 608, "height": 1080 },
  "content_aspect": 0.5629,
  "measured_frames": 300,
  "measured_duration_seconds": 10.0,
  "measured_frame_rate": 30.0,
  "unique_frames": 240,
  "unique_frame_rate": 24.0
}
```

`content_bounds` is the active picture inside the coded frame (cropdetect),
equal to the full frame when there are no bars - so `content_aspect` on a
1920x1080 file that reads 0.5629 is a vertical cut pillarboxed into a
landscape frame, which no container-level check can see.

`measured_*` come from the decode itself rather than from the container's
claims. `unique_frame_rate` counts distinct pictures (`mpdecimate`): a 24p
master padded into a 30p container measures 30 and 24 respectively.

`cut_points` lists detected scene changes as
`{ "time_seconds": 8.32, "score": 13.4 }`, scores on scdet's 0-100 scale.
The detection floor is deliberately low (4), because the intended consumer
compares one export against another: the same cut scores differently in a
16:9 and a 9:16 crop of one edit, since the crop changes how much of the
frame the cut moves. Comparing "was it detected" across crops produces
false mismatches; comparing "how strong was the change here" does not.

Every key is optional. A missing key means the pass did not produce that
number; it never means zero.

## `doctor` - runtime health

```bash
assetfox-cli doctor [--pretty]
```

Reports `media_info_lib` (`loaded`, resolved `path`, `errors[]`) and
`ffmpeg`/`ffprobe` (`available`, `path`, `source`). Orchestrators should call
it once at startup and refuse deep checks when ffmpeg is missing.
