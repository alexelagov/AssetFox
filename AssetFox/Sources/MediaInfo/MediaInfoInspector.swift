import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MediaInfoInspectionResult: Sendable {
    var deepMetadata: MediaInfoDeepMetadataResult?
    var rawFamily: String?
    var container: String?
    var profile: String?
    var codec: String?
    var resolution: String?
    var frameRate: String?
    var duration: String?
    var timecode: String?
    var overallBitRate: String?
    var encodedDate: String?
    var taggedDate: String?
    var writingApplication: String?
    var writingLibrary: String?
    var bitDepth: String?
    var pixelFormat: String?
    var colorSpace: String?
    var transferFunction: String?
    var colorPrimaries: String?
    var colorRange: String?
    var audioSummary: String?
    var videoTrackCount: Int?
    var audioTrackCount: Int?
    var metadataSource: String
    var warnings: [String]
}

struct MediaInfoInspector {
    func inspect(url: URL) async -> MediaInfoInspectionResult {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        let contentType = values?.contentType
        let rawFamily = rawFamily(for: url)

        let baseResult: MediaInfoInspectionResult
        if contentType?.conforms(to: .image) == true {
            baseResult = inspectImage(url: url, contentType: contentType, rawFamily: rawFamily)
        } else if contentType?.conforms(to: .movie) == true || contentType?.conforms(to: .video) == true || contentType?.conforms(to: .audio) == true || rawFamily != nil {
            baseResult = await inspectAVAsset(url: url, contentType: contentType, rawFamily: rawFamily)
        } else {
            baseResult = MediaInfoInspectionResult(
                deepMetadata: nil,
                rawFamily: rawFamily,
                container: contentType?.localizedDescription ?? url.pathExtension.uppercased().nonEmpty,
                profile: nil,
                codec: nil,
                resolution: nil,
                frameRate: nil,
                duration: nil,
                timecode: nil,
                overallBitRate: nil,
                encodedDate: nil,
                taggedDate: nil,
                writingApplication: nil,
                writingLibrary: nil,
                bitDepth: nil,
                pixelFormat: nil,
                colorSpace: nil,
                transferFunction: nil,
                colorPrimaries: nil,
                colorRange: nil,
                audioSummary: nil,
                videoTrackCount: nil,
                audioTrackCount: nil,
                metadataSource: "Filesystem",
                warnings: ["No native media parser is available for this file type yet."]
            )
        }

        let mediaInfoStatus = await MediaInfoLibService().inspect(url: url)

        let enrichedWithMediaInfo: MediaInfoInspectionResult
        switch mediaInfoStatus {
        case .metadata(let metadata):
            enrichedWithMediaInfo = mergeWithMediaInfoLib(baseResult, metadata: metadata, rawFamily: rawFamily)
        case .failed:
            enrichedWithMediaInfo = baseResult
        case .libraryUnavailable:
            enrichedWithMediaInfo = baseResult
        }

        let merged = mergeWithFFProbeIfAvailable(
            enrichedWithMediaInfo,
            url: url,
            rawFamily: rawFamily,
            allowFallback: !usesMediaInfoLib(enrichedWithMediaInfo.metadataSource)
        )
        return addAvailabilityWarnings(
            to: merged,
            rawFamily: rawFamily,
            contentType: contentType,
            mediaInfoStatus: mediaInfoStatus
        )
    }

    private func inspectImage(url: URL, contentType: UTType?, rawFamily: String?) -> MediaInfoInspectionResult {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return MediaInfoInspectionResult(
                deepMetadata: nil,
                rawFamily: rawFamily,
                container: contentType?.localizedDescription ?? url.pathExtension.uppercased().nonEmpty,
                profile: rawFamily ?? contentType?.localizedDescription ?? url.pathExtension.uppercased().nonEmpty,
            codec: nil,
            resolution: nil,
            frameRate: nil,
            duration: nil,
            timecode: nil,
            overallBitRate: nil,
            encodedDate: nil,
            taggedDate: nil,
            writingApplication: nil,
            writingLibrary: nil,
            bitDepth: nil,
            pixelFormat: nil,
            colorSpace: nil,
            transferFunction: nil,
            colorPrimaries: nil,
            colorRange: nil,
            audioSummary: nil,
            videoTrackCount: nil,
            audioTrackCount: nil,
            metadataSource: "ImageIO",
            warnings: ["ImageIO could not read metadata for this image."]
        )
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let depth = properties[kCGImagePropertyDepth] as? Int
        let colorModel = properties[kCGImagePropertyColorModel] as? String
        let profileName = properties[kCGImagePropertyProfileName] as? String

        return MediaInfoInspectionResult(
            deepMetadata: nil,
            rawFamily: rawFamily,
            container: contentType?.localizedDescription ?? url.pathExtension.uppercased().nonEmpty,
            profile: rawFamily ?? contentType?.localizedDescription ?? url.pathExtension.uppercased().nonEmpty,
            codec: nil,
            resolution: [width, height].compactMap { $0 }.count == 2 ? "\(width!) × \(height!)" : nil,
            frameRate: nil,
            duration: nil,
            timecode: nil,
            overallBitRate: nil,
            encodedDate: nil,
            taggedDate: nil,
            writingApplication: nil,
            writingLibrary: nil,
            bitDepth: depth.map { "\($0)-bit" },
            pixelFormat: nil,
            colorSpace: colorModel,
            transferFunction: nil,
            colorPrimaries: profileName,
            colorRange: nil,
            audioSummary: nil,
            videoTrackCount: nil,
            audioTrackCount: nil,
            metadataSource: "ImageIO",
            warnings: []
        )
    }

    private func inspectAVAsset(url: URL, contentType: UTType?, rawFamily: String?) async -> MediaInfoInspectionResult {
        let asset = AVURLAsset(url: url)

        do {
            async let durationValue = asset.load(.duration)
            async let videoTracks = asset.loadTracks(withMediaType: .video)
            async let audioTracks = asset.loadTracks(withMediaType: .audio)

            let (durationTime, loadedVideoTracks, loadedAudioTracks) = try await (durationValue, videoTracks, audioTracks)

            var profile = rawFamily ?? contentType?.localizedDescription ?? url.pathExtension.uppercased().nonEmpty
            var codec: String?
            var resolution: String?
            var frameRate: String?
            var bitDepth: String?
            let pixelFormat: String? = nil
            var colorSpace: String?
            var transferFunction: String?
            var colorPrimaries: String?
            var colorRange: String?

            if let videoTrack = loadedVideoTracks.first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transformedSize = naturalSize.applying(try await videoTrack.load(.preferredTransform))
                let width = Int(abs(transformedSize.width))
                let height = Int(abs(transformedSize.height))
                if width > 0 && height > 0 {
                    resolution = "\(width) × \(height)"
                }

                let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                if nominalFrameRate > 0 {
                    frameRate = String(format: "%.3f fps", nominalFrameRate).replacingOccurrences(of: ".000", with: "")
                }

                let descriptions = try await videoTrack.load(.formatDescriptions)
                if let firstDescription = descriptions.first {
                    codec = fourCCString(from: CMFormatDescriptionGetMediaSubType(firstDescription))
                }

                if let extensions = descriptions.first.flatMap({ CMFormatDescriptionGetExtensions($0) as? [String: Any] }) {
                    if let bits = extensions[kCMFormatDescriptionExtension_Depth as String] {
                        bitDepth = "\(bits)-bit"
                    }

                    colorSpace = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String
                    transferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String
                    colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
                    colorRange = nil

                    if let mediaType = extensions[kCMFormatDescriptionExtension_FormatName as String] as? String {
                        profile = mediaType
                    }
                }
            }

            let durationSeconds = CMTimeGetSeconds(durationTime)
            return MediaInfoInspectionResult(
                deepMetadata: nil,
                rawFamily: rawFamily,
                container: contentType?.localizedDescription ?? url.pathExtension.uppercased().nonEmpty,
                profile: profile,
                codec: codec,
                resolution: resolution,
                frameRate: frameRate,
                duration: durationSeconds.isFinite && durationSeconds > 0 ? Self.formatDuration(durationSeconds) : nil,
                timecode: nil,
                overallBitRate: nil,
                encodedDate: nil,
                taggedDate: nil,
                writingApplication: nil,
                writingLibrary: nil,
                bitDepth: bitDepth,
                pixelFormat: pixelFormat,
                colorSpace: colorSpace,
                transferFunction: transferFunction,
                colorPrimaries: colorPrimaries,
                colorRange: colorRange,
                audioSummary: audioSummary(for: loadedAudioTracks),
                videoTrackCount: loadedVideoTracks.count,
                audioTrackCount: loadedAudioTracks.count,
                metadataSource: "AVFoundation",
                warnings: []
            )
        } catch {
            return MediaInfoInspectionResult(
                deepMetadata: nil,
                rawFamily: rawFamily,
                container: contentType?.localizedDescription ?? url.pathExtension.uppercased().nonEmpty,
                profile: rawFamily ?? contentType?.localizedDescription ?? url.pathExtension.uppercased().nonEmpty,
                codec: nil,
                resolution: nil,
                frameRate: nil,
                duration: nil,
                timecode: nil,
                overallBitRate: nil,
                encodedDate: nil,
                taggedDate: nil,
                writingApplication: nil,
                writingLibrary: nil,
                bitDepth: nil,
                pixelFormat: nil,
                colorSpace: nil,
                transferFunction: nil,
                colorPrimaries: nil,
                colorRange: nil,
                audioSummary: nil,
                videoTrackCount: nil,
                audioTrackCount: nil,
                metadataSource: "AVFoundation",
                warnings: ["AVFoundation could not fully inspect this file: \(error.localizedDescription)"]
            )
        }
    }

    private func audioSummary(for tracks: [AVAssetTrack]) -> String? {
        guard !tracks.isEmpty else { return nil }
        return "\(tracks.count) stream\(tracks.count == 1 ? "" : "s")"
    }

    private func mergeWithMediaInfoLib(_ native: MediaInfoInspectionResult, metadata: MediaInfoDeepMetadataResult, rawFamily: String?) -> MediaInfoInspectionResult {
        var merged = native
        let primaryVideo = metadata.videoTracks.first
        let primaryAudio = metadata.audioTracks.first

        merged.deepMetadata = metadata
        merged.rawFamily = native.rawFamily ?? rawFamily
        merged.container = metadata.general.containerFormat ?? merged.container
        merged.profile = primaryVideo?.format ?? merged.profile
        merged.codec = primaryVideo?.codec ?? merged.codec
        merged.resolution = primaryVideo?.resolutionLabel ?? merged.resolution
        merged.frameRate = primaryVideo?.frameRate ?? merged.frameRate
        merged.duration = metadata.general.duration ?? merged.duration
        merged.timecode = primaryVideo?.timecode ?? merged.timecode
        merged.overallBitRate = metadata.general.overallBitRate ?? merged.overallBitRate
        merged.encodedDate = metadata.general.encodedDate ?? merged.encodedDate
        merged.taggedDate = metadata.general.taggedDate ?? merged.taggedDate
        merged.writingApplication = metadata.general.writingApplication ?? merged.writingApplication
        merged.writingLibrary = metadata.general.writingLibrary ?? merged.writingLibrary
        merged.bitDepth = primaryVideo?.bitDepth ?? primaryAudio?.bitDepth ?? merged.bitDepth
        merged.audioSummary = audioSummary(from: metadata.audioTracks) ?? merged.audioSummary
        merged.videoTrackCount = metadata.videoTracks.count
        merged.audioTrackCount = metadata.audioTracks.count
        merged.metadataSource = merged.metadataSource == "Filesystem" ? metadata.source.rawValue : "\(merged.metadataSource) + \(metadata.source.rawValue)"
        merged.warnings.append(contentsOf: metadata.warnings)
        merged.warnings.append(contentsOf: metadata.errors)
        return merged
    }

    private func mergeWithFFProbeIfAvailable(_ native: MediaInfoInspectionResult, url: URL, rawFamily: String?, allowFallback: Bool) -> MediaInfoInspectionResult {
        guard allowFallback else { return native }
        guard let executableURL = FFProbeAdapter.locateExecutable(),
              let probe = probeViaFFProbe(url: url, executableURL: executableURL) else {
            return native
        }

        var merged = native
        merged.rawFamily = native.rawFamily ?? probe.rawFamily ?? rawFamily
        merged.container = probe.container ?? native.container
        merged.profile = probe.profile ?? native.profile
        merged.codec = probe.codec ?? native.codec
        merged.resolution = probe.resolution ?? native.resolution
        merged.frameRate = probe.frameRate ?? native.frameRate
        merged.duration = probe.duration ?? native.duration
        merged.timecode = probe.timecode ?? native.timecode
        merged.overallBitRate = native.overallBitRate
        merged.encodedDate = native.encodedDate
        merged.taggedDate = native.taggedDate
        merged.writingApplication = native.writingApplication
        merged.writingLibrary = native.writingLibrary
        merged.bitDepth = probe.bitDepth ?? native.bitDepth
        merged.pixelFormat = probe.pixelFormat ?? native.pixelFormat
        merged.colorSpace = probe.colorSpace ?? native.colorSpace
        merged.transferFunction = probe.transferFunction ?? native.transferFunction
        merged.colorPrimaries = probe.colorPrimaries ?? native.colorPrimaries
        merged.colorRange = probe.colorRange ?? native.colorRange
        merged.audioSummary = probe.audioSummary ?? native.audioSummary
        merged.videoTrackCount = native.videoTrackCount
        merged.audioTrackCount = native.audioTrackCount
        merged.metadataSource = native.metadataSource == "Filesystem" ? "ffprobe" : "\(native.metadataSource) + ffprobe"
        return merged
    }

    private func probeViaFFProbe(url: URL, executableURL: URL) -> FFProbeMediaInfo? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-v", "error",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            url.path
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let format = object["format"] as? [String: Any]
        let streams = object["streams"] as? [[String: Any]] ?? []
        let videoStream = primaryVideoStream(from: streams)
        let audioStreams = streams.filter { ($0["codec_type"] as? String) == "audio" }
        let tags = format?["tags"] as? [String: Any]
        let streamTags = videoStream?["tags"] as? [String: Any]

        let codecName = sanitizeCodecName(
            (videoStream?["codec_long_name"] as? String)?.nonEmpty
            ?? (videoStream?["codec_name"] as? String)?.nonEmpty
            ?? (videoStream?["codec_tag_string"] as? String)?.nonEmpty
        )
        let profile = (videoStream?["profile"] as? String) ?? (format?["format_long_name"] as? String) ?? (format?["format_name"] as? String)
        let container = (format?["format_long_name"] as? String) ?? (format?["format_name"] as? String)
        let width = firstPositiveInt(in: videoStream, keys: ["width", "coded_width"])
        let height = firstPositiveInt(in: videoStream, keys: ["height", "coded_height"])
        let resolution: String? = if let width, let height, width > 0, height > 0 { "\(width) × \(height)" } else { nil }

        let rateText = (videoStream?["avg_frame_rate"] as? String) ?? (videoStream?["r_frame_rate"] as? String)
        let frameRate = rateText.flatMap(Self.parseRate).map { value in
            String(format: "%.3f fps", value).replacingOccurrences(of: ".000", with: "")
        }

        let duration = (format?["duration"] as? String).flatMap(Double.init).map(Self.formatDuration)
        let bitDepth = ((videoStream?["bits_per_raw_sample"] as? String) ?? (videoStream?["bits_per_sample"] as? Int).map(String.init))
            .flatMap { $0.nonEmpty }
            .map { "\($0)-bit" }

        let audioSummary = audioSummary(from: audioStreams)
        let rawFamily = rawFamily(from: codecName, container: container, profile: profile, extensionHint: url.pathExtension)

        return FFProbeMediaInfo(
            rawFamily: rawFamily,
            container: container,
            profile: profile,
            codec: codecName,
            resolution: resolution,
            frameRate: frameRate,
            duration: duration,
            timecode: firstTimecode(in: streams) ?? (streamTags?["timecode"] as? String)?.nonEmpty ?? (tags?["timecode"] as? String)?.nonEmpty,
            bitDepth: bitDepth ?? firstPositiveInt(in: videoStream, keys: ["bits_per_raw_sample", "bits_per_sample"]).map { "\($0)-bit" },
            pixelFormat: (videoStream?["pix_fmt"] as? String)?.nonEmpty,
            colorSpace: (videoStream?["color_space"] as? String)?.nonEmpty,
            transferFunction: (videoStream?["color_transfer"] as? String)?.nonEmpty,
            colorPrimaries: (videoStream?["color_primaries"] as? String)?.nonEmpty,
            colorRange: (videoStream?["color_range"] as? String)?.nonEmpty,
            audioSummary: audioSummary
        )
    }

    private func audioSummary(from streams: [[String: Any]]) -> String? {
        guard !streams.isEmpty else { return nil }

        let primary = streams.first
        let channels = primary?["channels"] as? Int
        let layout = (primary?["channel_layout"] as? String)?.nonEmpty
        let sampleRate = ((primary?["sample_rate"] as? String).flatMap(Int.init)).map { "\($0 / 1000) kHz" }

        var parts = ["\(streams.count) stream\(streams.count == 1 ? "" : "s")"]
        if let channels {
            parts.append("\(channels) ch")
        }
        if let layout {
            parts.append(layout)
        }
        if let sampleRate {
            parts.append(sampleRate)
        }

        return parts.joined(separator: " • ")
    }

    private func audioSummary(from tracks: [MediaInfoAudioTrackMetadata]) -> String? {
        guard !tracks.isEmpty else { return nil }

        var parts = ["\(tracks.count) stream\(tracks.count == 1 ? "" : "s")"]
        if let channels = tracks.first?.channelCount {
            parts.append(channels)
        }
        if let sampleRate = tracks.first?.sampleRate {
            parts.append(sampleRate)
        }

        return parts.joined(separator: " • ")
    }

    private func primaryVideoStream(from streams: [[String: Any]]) -> [String: Any]? {
        streams
            .filter { ($0["codec_type"] as? String) == "video" }
            .sorted { left, right in
                let leftScore = videoStreamScore(left)
                let rightScore = videoStreamScore(right)
                if leftScore == rightScore {
                    return videoStreamArea(left) > videoStreamArea(right)
                }
                return leftScore > rightScore
            }
            .first
    }

    private func videoStreamScore(_ stream: [String: Any]) -> Int {
        var score = 0

        let width = firstPositiveInt(in: stream, keys: ["width", "coded_width"]) ?? 0
        let height = firstPositiveInt(in: stream, keys: ["height", "coded_height"]) ?? 0

        if width > 0 { score += 5 }
        if height > 0 { score += 5 }
        if width > 0 && height > 0 { score += 8 }
        if ((stream["codec_long_name"] as? String)?.nonEmpty ?? (stream["codec_name"] as? String)?.nonEmpty ?? (stream["codec_tag_string"] as? String)?.nonEmpty) != nil {
            score += 5
        }
        if (stream["profile"] as? String)?.nonEmpty != nil { score += 2 }
        if (stream["pix_fmt"] as? String)?.nonEmpty != nil { score += 2 }
        let averageRate = (stream["avg_frame_rate"] as? String).flatMap(Self.parseRate)
        let nominalRate = (stream["r_frame_rate"] as? String).flatMap(Self.parseRate)
        if averageRate != nil || nominalRate != nil {
            score += 2
        }

        if let disposition = stream["disposition"] as? [String: Any],
           firstPositiveInt(in: disposition, keys: ["attached_pic"]) == 1 {
            score -= 20
        }

        return score
    }

    private func videoStreamArea(_ stream: [String: Any]) -> Int {
        let width = firstPositiveInt(in: stream, keys: ["width", "coded_width"]) ?? 0
        let height = firstPositiveInt(in: stream, keys: ["height", "coded_height"]) ?? 0
        return width * height
    }

    private func firstPositiveInt(in dictionary: [String: Any]?, keys: [String]) -> Int? {
        guard let dictionary else { return nil }

        for key in keys {
            if let value = dictionary[key] as? Int, value > 0 {
                return value
            }
            if let value = dictionary[key] as? Double, value > 0 {
                return Int(value)
            }
            if let value = dictionary[key] as? String,
               let parsed = Int(value),
               parsed > 0 {
                return parsed
            }
        }

        return nil
    }

    private func firstTimecode(in streams: [[String: Any]]) -> String? {
        for stream in streams {
            let tags = stream["tags"] as? [String: Any]
            if let timecode = (tags?["timecode"] as? String)?.nonEmpty {
                return timecode
            }
        }
        return nil
    }

    private func sanitizeCodecName(_ value: String?) -> String? {
        guard let value = value?.nonEmpty else { return nil }
        let normalized = value
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        if normalized == "[0][0][0][0]" || normalized == "0x00000000" {
            return nil
        }

        return value
    }

    private func addAvailabilityWarnings(to result: MediaInfoInspectionResult, rawFamily: String?, contentType: UTType?, mediaInfoStatus: MediaInfoLibService.Availability) -> MediaInfoInspectionResult {
        var updated = result
        let shouldPreferFFProbe = rawFamily != nil || contentType?.conforms(to: .movie) == true || contentType?.conforms(to: .video) == true

        if shouldPreferFFProbe && !usesMediaInfoLib(updated.metadataSource) && FFProbeAdapter.locateExecutable() == nil {
            updated.warnings.append("ffprobe is not available on this Mac, so RAW/container/codec fields may be incomplete.")
        }

        if case .failed(let errors) = mediaInfoStatus {
            updated.warnings.append(contentsOf: errors)
        }

        return updated
    }

    private func usesMediaInfoLib(_ source: String) -> Bool {
        source.localizedCaseInsensitiveContains("MediaInfoLib")
    }

    private func rawFamily(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "ari":
            return "ARRIRAW"
        case "braw":
            return "Blackmagic RAW"
        case "r3d":
            return "REDCODE RAW"
        case "dng":
            return "CinemaDNG / DNG"
        case "crm":
            return "Canon Cinema RAW Light"
        case "cr2", "cr3":
            return "Canon RAW"
        case "nef":
            return "Nikon RAW"
        case "arw", "sr2", "srf":
            return "Sony RAW"
        case "raf":
            return "Fujifilm RAW"
        case "orf":
            return "Olympus RAW"
        case "rw2":
            return "Panasonic RAW"
        case "iiq":
            return "Phase One RAW"
        case "3fr":
            return "Hasselblad RAW"
        default:
            return nil
        }
    }

    private func rawFamily(from codecName: String?, container: String?, profile: String?, extensionHint: String) -> String? {
        let candidates = [codecName, container, profile, extensionHint]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if candidates.contains("arriraw") || candidates.contains("arri raw") {
            return "ARRIRAW"
        }
        if candidates.contains("blackmagic raw") || candidates.contains("braw") {
            return "Blackmagic RAW"
        }
        if candidates.contains("redcode") || candidates.contains("r3d") {
            return "REDCODE RAW"
        }
        if candidates.contains("cinemadng") || candidates.contains("dng") {
            return "CinemaDNG / DNG"
        }
        if candidates.contains("canon cinema raw") || candidates.contains("canon raw") || extensionHint.lowercased() == "crm" {
            return "Canon Cinema RAW"
        }
        return rawFamily(for: URL(fileURLWithPath: "placeholder.\(extensionHint)"))
    }

    private static func parseRate(_ text: String) -> Double? {
        if let value = Double(text), value > 0 {
            return value
        }

        let parts = text.split(separator: "/")
        guard parts.count == 2,
              let numerator = Double(parts[0]),
              let denominator = Double(parts[1]),
              denominator != 0 else {
            return nil
        }

        return numerator / denominator
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        let hours = rounded / 3600
        let minutes = (rounded % 3600) / 60
        let secs = rounded % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func fourCCString(from value: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar((value >> 24) & 0xff),
            CChar((value >> 16) & 0xff),
            CChar((value >> 8) & 0xff),
            CChar(value & 0xff),
            0
        ]

        let utf8Bytes = bytes.dropLast().map { UInt8(bitPattern: $0) }
        if let string = String(validating: utf8Bytes, as: UTF8.self),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return string
        }

        return String(format: "0x%08X", value)
    }
}

private struct FFProbeMediaInfo {
    var rawFamily: String?
    var container: String?
    var profile: String?
    var codec: String?
    var resolution: String?
    var frameRate: String?
    var duration: String?
    var timecode: String?
    var bitDepth: String?
    var pixelFormat: String?
    var colorSpace: String?
    var transferFunction: String?
    var colorPrimaries: String?
    var colorRange: String?
    var audioSummary: String?
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
