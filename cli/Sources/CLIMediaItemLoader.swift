import AVFoundation
import Foundation

// Mirrors QualityCheckViewModel item loading so CLI runs and app runs agree:
// transformed natural size, nominal frame rate, filesystem size.
struct CLIMediaItemLoader {
    struct LoadedMedia {
        let item: QualityCheckVideoItem
        let warnings: [String]
    }

    func load(url: URL) async -> LoadedMedia {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let asset = AVURLAsset(url: url)

        do {
            async let durationValue = asset.load(.duration)
            async let videoTracks = asset.loadTracks(withMediaType: .video)

            let (durationTime, loadedVideoTracks) = try await (durationValue, videoTracks)
            let videoTrack = loadedVideoTracks.first
            let naturalSize = try await videoTrack?.load(.naturalSize) ?? .zero
            let transform = try await videoTrack?.load(.preferredTransform) ?? .identity
            let transformedSize = naturalSize.applying(transform)
            let nominalFrameRate = Double(try await videoTrack?.load(.nominalFrameRate) ?? 0)
            let durationSeconds = CMTimeGetSeconds(durationTime)

            let item = QualityCheckVideoItem(
                url: url,
                durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
                naturalSize: CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height)),
                nominalFrameRate: nominalFrameRate,
                fileSize: fileSize
            )
            return LoadedMedia(item: item, warnings: [])
        } catch {
            let item = QualityCheckVideoItem(url: url, fileSize: fileSize)
            return LoadedMedia(
                item: item,
                warnings: ["AVFoundation could not load timing metadata: \(error.localizedDescription)"]
            )
        }
    }
}
