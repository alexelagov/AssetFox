import Foundation

enum MediaInfoDeepMetadataSource: String, Sendable {
    case mediaInfoLib = "MediaInfoLib"
}

struct MediaInfoGeneralMetadata: Sendable {
    var completeName: String?
    var containerFormat: String?
    var formatProfile: String?
    var codecID: String?
    var fileSize: String?
    var duration: String?
    var overallBitRateMode: String?
    var overallBitRate: String?
    var frameRate: String?
    var encodedDate: String?
    var taggedDate: String?
    var writingApplication: String?
    var writingLibrary: String?
}

struct MediaInfoVideoTrackMetadata: Identifiable, Sendable {
    var id: Int { index }

    let index: Int
    var streamID: String?
    var format: String?
    var formatVersion: String?
    var formatProfile: String?
    var codecID: String?
    var codec: String?
    var duration: String?
    var bitRateMode: String?
    var bitRate: String?
    var width: Int?
    var height: Int?
    var displayAspectRatio: String?
    var frameRateMode: String?
    var frameRate: String?
    var colorSpace: String?
    var chromaSubsampling: String?
    var scanType: String?
    var bitsPerPixelFrame: String?
    var streamSize: String?
    var writingLibrary: String?
    var encodedDate: String?
    var taggedDate: String?
    var bitDepth: String?
    var timecode: String?
    var pixelFormat: String?
    var colorPrimaries: String?
    var matrixCoefficients: String?
    var gamma: String?

    var resolutionLabel: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width) × \(height)"
    }
}

struct MediaInfoAudioTrackMetadata: Identifiable, Sendable {
    var id: Int { index }

    let index: Int
    var streamID: String?
    var format: String?
    var formatSettings: String?
    var codecID: String?
    var codec: String?
    var duration: String?
    var bitRateMode: String?
    var bitRate: String?
    var channelCount: String?
    var channelLayout: String?
    var sampleRate: String?
    var bitDepth: String?
    var streamSize: String?
    var defaultFlag: String?
    var alternateGroup: String?
    var encodedDate: String?
    var taggedDate: String?
}

struct MediaInfoDeepMetadataResult: Sendable {
    var general: MediaInfoGeneralMetadata
    var videoTracks: [MediaInfoVideoTrackMetadata]
    var audioTracks: [MediaInfoAudioTrackMetadata]
    var source: MediaInfoDeepMetadataSource
    var warnings: [String]
    var errors: [String]
}
