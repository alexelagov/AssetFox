import Foundation

struct MediaInfoLibService {
    enum Availability {
        case metadata(MediaInfoDeepMetadataResult)
        case libraryUnavailable([String])
        case failed([String])
    }

    func inspect(url: URL) async -> Availability {
        await Task.detached(priority: .userInitiated) {
            inspectSynchronously(url: url)
        }.value
    }

    private func inspectSynchronously(url: URL) -> Availability {
        let payload = MediaInfoLibBridge.inspectFile(atPath: url.path)
        let status = (payload["status"] as? String) ?? "error"
        let warnings = payload["warnings"] as? [String] ?? []
        let errors = payload["errors"] as? [String] ?? []

        switch status {
        case "libraryUnavailable":
            return .libraryUnavailable(errors)
        case "success":
            guard let json = payload["json"] as? String,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let metadata = parseMetadata(from: object, warnings: warnings, errors: errors) else {
                return .failed(errors.isEmpty ? ["MediaInfoLib returned an unreadable JSON payload."] : errors)
            }
            return .metadata(metadata)
        default:
            return .failed(errors.isEmpty ? ["MediaInfoLib inspection failed."] : errors)
        }
    }

    private func parseMetadata(from object: [String: Any], warnings: [String], errors: [String]) -> MediaInfoDeepMetadataResult? {
        guard let media = object["media"] as? [String: Any],
              let tracks = media["track"] as? [[String: Any]],
              !tracks.isEmpty else {
            return nil
        }

        let generalTrack = tracks.first(where: { stringValue(in: $0, keys: ["@type"]) == "General" }) ?? [:]
        let videoTracks = tracks
            .filter { stringValue(in: $0, keys: ["@type"]) == "Video" }
            .enumerated()
            .map(mapVideoTrack)
        let audioTracks = tracks
            .filter { stringValue(in: $0, keys: ["@type"]) == "Audio" }
            .enumerated()
            .map(mapAudioTrack)

        let general = MediaInfoGeneralMetadata(
            completeName: stringValue(in: generalTrack, keys: ["CompleteName", "Complete name"]),
            containerFormat: stringValue(in: generalTrack, keys: ["Format", "InternetMediaType"]),
            formatVersion: stringValue(in: generalTrack, keys: ["Format_Version", "Format version"]),
            formatProfile: stringValue(in: generalTrack, keys: ["Format_Profile", "Format profile"]),
            formatSettings: stringValue(in: generalTrack, keys: ["Format_Settings", "Format settings"]),
            codecID: stringValue(in: generalTrack, keys: ["CodecID", "CodecID/String"]),
            fileSize: fileSizeString(from: generalTrack),
            duration: durationString(from: generalTrack),
            overallBitRateMode: stringValue(in: generalTrack, keys: ["OverallBitRate_Mode", "Overall bit rate mode"]),
            overallBitRate: bitRateString(from: generalTrack, keys: ["OverallBitRate", "BitRate"]),
            frameRate: stringValue(in: generalTrack, keys: ["FrameRate/String", "FrameRate"]),
            encodedDate: stringValue(in: generalTrack, keys: ["Encoded_Date", "Encoded date"]),
            taggedDate: stringValue(in: generalTrack, keys: ["Tagged_Date", "Tagged date"]),
            writingApplication: stringValue(in: generalTrack, keys: ["Encoded_Application_String", "Encoded_Application", "EncodedApplication", "Encoded application", "WritingApplication", "Writing application"]),
            writingLibrary: stringValue(in: generalTrack, keys: ["Encoded_Library_String", "Encoded_Library", "EncodedLibrary", "Encoded library", "WritingLibrary", "Writing library"]),
            isStreamable: stringValue(in: generalTrack, keys: ["IsStreamable"])
        )

        return MediaInfoDeepMetadataResult(
            general: general,
            videoTracks: videoTracks,
            audioTracks: audioTracks,
            source: .mediaInfoLib,
            warnings: warnings,
            errors: errors
        )
    }

    private func mapVideoTrack(_ element: (offset: Int, element: [String: Any])) -> MediaInfoVideoTrackMetadata {
        let track = element.element
        return MediaInfoVideoTrackMetadata(
            index: element.offset,
            streamID: stringValue(in: track, keys: ["ID", "StreamOrder"]),
            format: stringValue(in: track, keys: ["Format", "Format_Commercial_IfAny"]),
            formatVersion: stringValue(in: track, keys: ["Format_Version", "Format version"]),
            formatProfile: stringValue(in: track, keys: ["Format_Profile", "Format profile"]),
            codecID: stringValue(in: track, keys: ["CodecID", "CodecID/String", "CodecID/Hint", "CodecID/Info"]),
            codec: stringValue(in: track, keys: ["CodecID/Hint", "CodecID", "CodecID/Info", "Format"]),
            duration: durationString(from: track),
            bitRateMode: stringValue(in: track, keys: ["BitRate_Mode", "Bit rate mode"]),
            bitRate: bitRateString(from: track, keys: ["BitRate"]),
            width: intValue(in: track, keys: ["Width", "Stored_Width"]),
            height: intValue(in: track, keys: ["Height", "Stored_Height"]),
            widthDisplay: stringValue(in: track, keys: ["Width_String", "Width/String"]),
            heightDisplay: stringValue(in: track, keys: ["Height_String", "Height/String"]),
            displayAspectRatio: stringValue(in: track, keys: ["DisplayAspectRatio_String", "DisplayAspectRatio/String", "DisplayAspectRatio"]),
            frameRateMode: stringValue(in: track, keys: ["FrameRate_Mode", "Frame rate mode"]),
            frameRate: stringValue(in: track, keys: ["FrameRate/String", "FrameRate"]),
            colorSpace: stringValue(in: track, keys: ["ColorSpace", "colour_space"]),
            chromaSubsampling: stringValue(in: track, keys: ["ChromaSubsampling", "Chroma subsampling"]),
            scanType: stringValue(in: track, keys: ["ScanType_String", "ScanType"]),
            bitsPerPixelFrame: stringValue(in: track, keys: ["Bits-(Pixel*Frame)", "Bits__Pixel_Frame_"]),
            streamSize: streamSizeString(from: track),
            writingLibrary: stringValue(in: track, keys: ["Encoded_Library", "EncodedLibrary", "Encoded library", "WritingLibrary", "Writing library"]),
            encodedDate: stringValue(in: track, keys: ["Encoded_Date", "Encoded date"]),
            taggedDate: stringValue(in: track, keys: ["Tagged_Date", "Tagged date"]),
            bitDepth: bitDepthString(from: track, keys: ["BitDepth", "BitDepth/String"]),
            timecode: stringValue(in: track, keys: ["TimeCode_FirstFrame", "TimeCode_of_FirstFrame", "TimeCode/String", "TimeCode"]),
            pixelFormat: stringValue(in: track, keys: ["PixelFormat", "PixelFormat/String"]),
            colorPrimaries: stringValue(in: track, keys: ["colour_primaries", "ColorPrimaries", "Color primaries"]),
            matrixCoefficients: stringValue(in: track, keys: ["matrix_coefficients", "MatrixCoefficients", "Matrix coefficients"]),
            gamma: stringValue(in: track, keys: ["Gamma"]),
            // The raw keys, not the _String variants: "Yes"/"No" and
            // "M=4, N=24" are the machine-readable spellings.
            formatSettingsCABAC: stringValue(in: track, keys: ["Format_Settings_CABAC"]),
            formatSettingsRefFrames: stringValue(in: track, keys: ["Format_Settings_RefFrames"]),
            formatSettingsGOP: stringValue(in: track, keys: ["Format_Settings_GOP"])
        )
    }

    private func mapAudioTrack(_ element: (offset: Int, element: [String: Any])) -> MediaInfoAudioTrackMetadata {
        let track = element.element
        return MediaInfoAudioTrackMetadata(
            index: element.offset,
            streamID: stringValue(in: track, keys: ["ID", "StreamOrder"]),
            format: stringValue(in: track, keys: ["Format", "Format_Commercial_IfAny"]),
            formatSettings: stringValue(in: track, keys: ["Format_Settings", "Format settings"]),
            codecID: stringValue(in: track, keys: ["CodecID", "CodecID/String", "CodecID/Hint", "CodecID/Info"]),
            codec: stringValue(in: track, keys: ["CodecID/Hint", "CodecID", "CodecID/Info", "Format"]),
            duration: durationString(from: track),
            bitRateMode: stringValue(in: track, keys: ["BitRate_Mode_String", "BitRate_Mode", "Bit rate mode"]),
            bitRate: bitRateString(from: track, keys: ["BitRate"]),
            channelCount: stringValue(in: track, keys: ["Channels_String", "Channel(s)", "Channel_s_", "Channels"]),
            channelLayout: stringValue(in: track, keys: ["ChannelLayout", "ChannelLayout/String", "Channel layout"]),
            sampleRate: stringValue(in: track, keys: ["SamplingRate/String", "SamplingRate"]),
            bitDepth: bitDepthString(from: track, keys: ["BitDepth", "BitDepth/String"]),
            streamSize: streamSizeString(from: track),
            defaultFlag: stringValue(in: track, keys: ["Default"]),
            alternateGroup: stringValue(in: track, keys: ["AlternateGroup", "Alternate group"]),
            encodedDate: stringValue(in: track, keys: ["Encoded_Date", "Encoded date"]),
            taggedDate: stringValue(in: track, keys: ["Tagged_Date", "Tagged date"])
        )
    }

    private func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in expandedKeyVariants(for: keys) {
            if let value = dictionary[key] as? String {
                let cleaned = cleanedString(value)
                if cleaned != nil { return cleaned }
            } else if let value = dictionary[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private func intValue(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? NSNumber {
                return value.intValue > 0 ? value.intValue : nil
            }
            if let value = dictionary[key] as? String {
                let digits = value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let parsed = Int(digits), parsed > 0 {
                    return parsed
                }
            }
        }
        return nil
    }

    private func cleanedString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "[0][0][0][0]" || trimmed == "0x00000000" {
            return nil
        }
        return trimmed
    }

    private func durationString(from dictionary: [String: Any]) -> String? {
        if let text = stringValue(in: dictionary, keys: [
            "Duration_String",
            "Duration/String",
            "Duration_String1",
            "Duration_String2",
            "Duration_String3",
            "Duration_String4",
            "Duration_String5",
            "Duration"
        ]) {
            if let rawMilliseconds = Double(text), rawMilliseconds > 0 {
                return formatDuration(milliseconds: rawMilliseconds)
            }
            return text
        }
        return nil
    }

    private func bitRateString(from dictionary: [String: Any], keys: [String]) -> String? {
        let stringKeys = keys.flatMap { ["\($0)_String", "\($0)/String", $0] }
        if let text = stringValue(in: dictionary, keys: stringKeys) {
            if let rawBitRate = Double(text), rawBitRate > 0 {
                return formatBitRate(rawBitRate)
            }
            return text
        }
        return nil
    }

    private func bitDepthString(from dictionary: [String: Any], keys: [String]) -> String? {
        guard let value = stringValue(in: dictionary, keys: keys) else { return nil }
        return value.lowercased().contains("bit") ? value : "\(value)-bit"
    }

    private func formatDuration(milliseconds: Double) -> String {
        let roundedSeconds = Int((milliseconds / 1000.0).rounded())
        let hours = roundedSeconds / 3600
        let minutes = (roundedSeconds % 3600) / 60
        let seconds = roundedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatBitRate(_ rawValue: Double) -> String {
        if rawValue >= 1_000_000_000 {
            return String(format: "%.2f Gb/s", rawValue / 1_000_000_000)
        }
        if rawValue >= 1_000_000 {
            return String(format: "%.2f Mb/s", rawValue / 1_000_000)
        }
        if rawValue >= 1_000 {
            return String(format: "%.2f kb/s", rawValue / 1_000)
        }
        return String(format: "%.0f b/s", rawValue)
    }

    private func fileSizeString(from dictionary: [String: Any]) -> String? {
        if let text = stringValue(in: dictionary, keys: [
            "FileSize_String",
            "FileSize/String",
            "FileSize_String1",
            "FileSize_String2",
            "FileSize_String3",
            "FileSize_String4",
            "FileSize_String5",
            "FileSize"
        ]) {
            if let rawBytes = Double(text), rawBytes > 0 {
                return ByteCountFormatter.string(fromByteCount: Int64(rawBytes.rounded()), countStyle: .file)
            }
            return text
        }
        return nil
    }

    private func streamSizeString(from dictionary: [String: Any]) -> String? {
        if let text = stringValue(in: dictionary, keys: [
            "StreamSize_String",
            "StreamSize/String",
            "StreamSize_String1",
            "StreamSize_String2",
            "StreamSize_String3",
            "StreamSize_String4",
            "StreamSize_String5",
            "StreamSize"
        ]) {
            if let rawBytes = Double(text), rawBytes > 0 {
                return ByteCountFormatter.string(fromByteCount: Int64(rawBytes.rounded()), countStyle: .file)
            }
            return text
        }
        return nil
    }

    private func expandedKeyVariants(for keys: [String]) -> [String] {
        var variants: [String] = []

        for key in keys {
            variants.append(key)

            let slashToUnderscore = key.replacingOccurrences(of: "/", with: "_")
            if slashToUnderscore != key {
                variants.append(slashToUnderscore)
            }

            let spaceToUnderscore = key.replacingOccurrences(of: " ", with: "_")
            if spaceToUnderscore != key {
                variants.append(spaceToUnderscore)
            }

            let combined = slashToUnderscore.replacingOccurrences(of: " ", with: "_")
            if combined != slashToUnderscore {
                variants.append(combined)
            }
        }

        return Array(NSOrderedSet(array: variants)) as? [String] ?? variants
    }
}
