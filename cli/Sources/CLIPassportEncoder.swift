import Foundation

// Serializes one inspected file into the "file passport" JSON contract
// (docs/CLI.md). Three layers with distinct trust levels:
//   av         - numeric values from AVFoundation, for machine comparison
//   summary    - merged display fields from MediaInfoInspector
//   media_info - raw MediaInfoLib track fields, display-formatted strings
struct CLIPassportEncoder {
    func passport(
        path: String,
        inspection: MediaInfoInspectionResult,
        item: QualityCheckVideoItem,
        loaderWarnings: [String]
    ) -> [String: Any] {
        var passport: [String: Any] = [
            "path": path,
            "file_name": (path as NSString).lastPathComponent,
            "file_size_bytes": item.fileSize
        ]

        var av: [String: Any] = [:]
        if item.durationSeconds > 0 {
            av["duration_seconds"] = item.durationSeconds
        }
        if item.naturalSize.width > 0, item.naturalSize.height > 0 {
            av["width"] = Int(item.naturalSize.width)
            av["height"] = Int(item.naturalSize.height)
        }
        if item.nominalFrameRate > 0 {
            av["nominal_frame_rate"] = item.nominalFrameRate
        }
        if !av.isEmpty {
            passport["av"] = av
        }

        passport["summary"] = summary(from: inspection)

        if let deep = inspection.deepMetadata {
            passport["media_info"] = mediaInfo(from: deep)
        }

        if let ffprobe = ffprobe(from: inspection) {
            passport["ffprobe"] = ffprobe
        }

        let warnings = loaderWarnings + inspection.warnings + (inspection.deepMetadata?.warnings ?? [])
        if !warnings.isEmpty {
            passport["warnings"] = warnings
        }
        let errors = inspection.deepMetadata?.errors ?? []
        if !errors.isEmpty {
            passport["errors"] = errors
        }

        return passport
    }

    func unreadablePassport(path: String, reason: String) -> [String: Any] {
        [
            "path": path,
            "file_name": (path as NSString).lastPathComponent,
            "error": reason
        ]
    }

    private func summary(from inspection: MediaInfoInspectionResult) -> [String: Any] {
        var summary: [String: Any] = [
            "metadata_source": inspection.metadataSource
        ]
        summary.setIfPresent("raw_family", inspection.rawFamily)
        summary.setIfPresent("container", inspection.container)
        summary.setIfPresent("profile", inspection.profile)
        summary.setIfPresent("codec", inspection.codec)
        summary.setIfPresent("resolution", inspection.resolution)
        summary.setIfPresent("frame_rate", inspection.frameRate)
        summary.setIfPresent("duration", inspection.duration)
        summary.setIfPresent("timecode", inspection.timecode)
        summary.setIfPresent("overall_bit_rate", inspection.overallBitRate)
        summary.setIfPresent("encoded_date", inspection.encodedDate)
        summary.setIfPresent("tagged_date", inspection.taggedDate)
        summary.setIfPresent("writing_application", inspection.writingApplication)
        summary.setIfPresent("writing_library", inspection.writingLibrary)
        summary.setIfPresent("bit_depth", inspection.bitDepth)
        summary.setIfPresent("pixel_format", inspection.pixelFormat)
        summary.setIfPresent("color_space", inspection.colorSpace)
        summary.setIfPresent("transfer_function", inspection.transferFunction)
        summary.setIfPresent("color_primaries", inspection.colorPrimaries)
        summary.setIfPresent("color_range", inspection.colorRange)
        summary.setIfPresent("audio_summary", inspection.audioSummary)
        summary.setIfPresent("video_track_count", inspection.videoTrackCount)
        summary.setIfPresent("audio_track_count", inspection.audioTrackCount)
        return summary
    }

    // Fourth layer: ffprobe's own measurement of the primary video stream.
    // MediaInfo does not report bit depth for ProRes QuickTime files, and
    // the AVFoundation depth is bits per pixel, so pix_fmt is the one
    // measured per-channel source left; the derived value names where it
    // came from so the consumer can weigh it. Absent entirely when ffprobe
    // was unavailable or gave no pixel format - absence stays "could not
    // verify", never a default.
    private func ffprobe(from inspection: MediaInfoInspectionResult) -> [String: Any]? {
        guard let pixelFormat = inspection.ffprobePixelFormat else {
            return nil
        }
        var payload: [String: Any] = ["pix_fmt": pixelFormat]
        if let bits = PixelFormatBitDepth.bitsPerChannel(fromPixelFormat: pixelFormat) {
            payload["video_bit_depth"] = bits
            payload["video_bit_depth_source"] = "pix_fmt"
        }
        return payload
    }

    private func mediaInfo(from deep: MediaInfoDeepMetadataResult) -> [String: Any] {
        [
            "source": deep.source.rawValue,
            "general": general(from: deep.general),
            "video_tracks": deep.videoTracks.map(videoTrack(from:)),
            "audio_tracks": deep.audioTracks.map(audioTrack(from:))
        ]
    }

    private func general(from general: MediaInfoGeneralMetadata) -> [String: Any] {
        var payload: [String: Any] = [:]
        payload.setIfPresent("complete_name", general.completeName)
        payload.setIfPresent("container_format", general.containerFormat)
        payload.setIfPresent("format_version", general.formatVersion)
        payload.setIfPresent("format_profile", general.formatProfile)
        payload.setIfPresent("format_settings", general.formatSettings)
        payload.setIfPresent("codec_id", general.codecID)
        payload.setIfPresent("file_size", general.fileSize)
        payload.setIfPresent("duration", general.duration)
        payload.setIfPresent("overall_bit_rate_mode", general.overallBitRateMode)
        payload.setIfPresent("overall_bit_rate", general.overallBitRate)
        payload.setIfPresent("frame_rate", general.frameRate)
        payload.setIfPresent("encoded_date", general.encodedDate)
        payload.setIfPresent("tagged_date", general.taggedDate)
        payload.setIfPresent("writing_application", general.writingApplication)
        payload.setIfPresent("writing_library", general.writingLibrary)
        // "The moov atom sits before the media data" as a boolean - what
        // web_streaming checks. Absent where the container has no such
        // concept, and that absence is the honest answer.
        payload.setIfPresent("is_streamable", yesNo(general.isStreamable))
        return payload
    }

    private func videoTrack(from track: MediaInfoVideoTrackMetadata) -> [String: Any] {
        var payload: [String: Any] = ["index": track.index]
        payload.setIfPresent("stream_id", track.streamID)
        payload.setIfPresent("format", track.format)
        payload.setIfPresent("format_version", track.formatVersion)
        payload.setIfPresent("format_profile", track.formatProfile)
        payload.setIfPresent("codec_id", track.codecID)
        payload.setIfPresent("codec", track.codec)
        payload.setIfPresent("duration", track.duration)
        payload.setIfPresent("bit_rate_mode", track.bitRateMode)
        payload.setIfPresent("bit_rate", track.bitRate)
        payload.setIfPresent("width", track.width)
        payload.setIfPresent("height", track.height)
        payload.setIfPresent("display_aspect_ratio", track.displayAspectRatio)
        payload.setIfPresent("frame_rate_mode", track.frameRateMode)
        payload.setIfPresent("frame_rate", track.frameRate)
        payload.setIfPresent("color_space", track.colorSpace)
        payload.setIfPresent("chroma_subsampling", track.chromaSubsampling)
        payload.setIfPresent("scan_type", track.scanType)
        payload.setIfPresent("bits_per_pixel_frame", track.bitsPerPixelFrame)
        payload.setIfPresent("stream_size", track.streamSize)
        payload.setIfPresent("writing_library", track.writingLibrary)
        payload.setIfPresent("encoded_date", track.encodedDate)
        payload.setIfPresent("tagged_date", track.taggedDate)
        payload.setIfPresent("bit_depth", track.bitDepth)
        payload.setIfPresent("timecode", track.timecode)
        payload.setIfPresent("pixel_format", track.pixelFormat)
        payload.setIfPresent("color_primaries", track.colorPrimaries)
        payload.setIfPresent("matrix_coefficients", track.matrixCoefficients)
        payload.setIfPresent("gamma", track.gamma)
        // Encoding settings for the delivery checker's machine rules:
        // booleans and numbers rather than MediaInfo's display strings, so
        // the consumer never string-matches "Yes".
        payload.setIfPresent("format_settings_cabac", yesNo(track.formatSettingsCABAC))
        payload.setIfPresent("format_settings_ref_frames", wholeNumber(track.formatSettingsRefFrames))
        payload.setIfPresent("format_settings_gop", track.formatSettingsGOP)
        return payload
    }

    /// MediaInfo answers set questions with "Yes"/"No" strings; the passport
    /// speaks JSON, where that fact is a boolean.
    private func yesNo(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "yes": return true
        case "no": return false
        default: return nil
        }
    }

    private func wholeNumber(_ value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
    }

    private func audioTrack(from track: MediaInfoAudioTrackMetadata) -> [String: Any] {
        var payload: [String: Any] = ["index": track.index]
        payload.setIfPresent("stream_id", track.streamID)
        payload.setIfPresent("format", track.format)
        payload.setIfPresent("format_settings", track.formatSettings)
        payload.setIfPresent("codec_id", track.codecID)
        payload.setIfPresent("codec", track.codec)
        payload.setIfPresent("duration", track.duration)
        payload.setIfPresent("bit_rate_mode", track.bitRateMode)
        payload.setIfPresent("bit_rate", track.bitRate)
        payload.setIfPresent("channel_count", track.channelCount)
        payload.setIfPresent("channel_layout", track.channelLayout)
        payload.setIfPresent("sample_rate", track.sampleRate)
        payload.setIfPresent("bit_depth", track.bitDepth)
        payload.setIfPresent("stream_size", track.streamSize)
        payload.setIfPresent("default_flag", track.defaultFlag)
        payload.setIfPresent("alternate_group", track.alternateGroup)
        payload.setIfPresent("encoded_date", track.encodedDate)
        payload.setIfPresent("tagged_date", track.taggedDate)
        return payload
    }
}
