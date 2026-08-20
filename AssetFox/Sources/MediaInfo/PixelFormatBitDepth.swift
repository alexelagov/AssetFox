import Foundation

/// Bits per colour channel as stated by an ffprobe pix_fmt name.
///
/// MediaInfo does not report bit depth for ProRes QuickTime files, and
/// AVFoundation's depth is bits per pixel (24 for 8-bit 4:2:2), so for
/// those files the decoded pixel format is the one honest source left:
/// its name carries the per-channel depth as a trailing digit token
/// ("yuv422p10le" is 10-bit), optionally followed by an endianness
/// suffix, and planar names without the token are 8-bit ("yuv420p").
///
/// The parse is deliberately narrow. Only the families whose names follow
/// that convention are read - planar YUV, planar RGB and grayscale. In
/// packed-format names the trailing digits mean something else (nv12's
/// "12" is a layout name, rgb24's "24" is bits per pixel), so everything
/// outside the whitelist returns nil, as does a derived number that is
/// not a real per-channel depth (gbrpf32le's float "32"). nil means "the
/// name does not state a depth", never 8.
enum PixelFormatBitDepth {
    private static let knownDepths: Set<Int> = [8, 9, 10, 12, 14, 16]

    static func bitsPerChannel(fromPixelFormat pixelFormat: String?) -> Int? {
        guard let name = pixelFormat?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !name.isEmpty else {
            return nil
        }
        guard name.hasPrefix("yuv") || name.hasPrefix("gbr") || name.hasPrefix("gray") else {
            return nil
        }

        var stem = Substring(name)
        if stem.hasSuffix("le") || stem.hasSuffix("be"), stem.dropLast(2).last?.isWholeNumber == true {
            stem = stem.dropLast(2)
        }

        var token = ""
        while let last = stem.last, last.isWholeNumber {
            token.insert(last, at: token.startIndex)
            stem = stem.dropLast()
        }

        if token.isEmpty {
            // The chroma digits sit before the planar marker ("yuv422p"),
            // so an empty trailing token is the convention's way of saying
            // 8-bit, not a failure to parse.
            return 8
        }
        guard let value = Int(token), knownDepths.contains(value) else {
            return nil
        }
        return value
    }
}
