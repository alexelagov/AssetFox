import Foundation

// Runs inside the assetfox-tests runner (see Package.swift): called from the
// @main entry point, exits non-zero on the first failed assertion.
struct PixelFormatBitDepthTests {
    static func run() {
        testDepthTokensAreRead()
        testPlanarNamesWithoutATokenAreEightBit()
        testPackedAndUnknownNamesStateNoDepth()
        testImplausibleTokensStateNoDepth()
        print("PixelFormatBitDepthTests passed")
    }

    private static func testDepthTokensAreRead() {
        let cases: [(String, Int)] = [
            ("yuv422p10le", 10),   // ProRes 422 family - the live gap this parser closes
            ("yuv420p10le", 10),
            ("yuv444p12le", 12),
            ("yuva444p12be", 12),
            ("yuv422p16", 16),
            ("yuv420p9le", 9),
            ("gbrp10le", 10),
            ("gbrap12le", 12),
            ("gray16be", 16),
            ("gray10le", 10),
            ("YUV422P10LE", 10),   // case-insensitive: the value is data, not spelling
            (" yuv422p10le ", 10)
        ]
        for (name, expected) in cases {
            assertEqual(PixelFormatBitDepth.bitsPerChannel(fromPixelFormat: name), expected, "\(name) should read as \(expected)-bit")
        }
    }

    private static func testPlanarNamesWithoutATokenAreEightBit() {
        for name in ["yuv420p", "yuv422p", "yuv444p", "yuvj420p", "yuvj444p", "yuva420p", "gbrp", "gbrap", "gray"] {
            assertEqual(PixelFormatBitDepth.bitsPerChannel(fromPixelFormat: name), 8, "\(name) should read as 8-bit")
        }
    }

    private static func testPackedAndUnknownNamesStateNoDepth() {
        // Trailing digits that are NOT a per-channel depth: nv12's "12" is a
        // layout name, rgb24/rgb48 count bits per pixel, y210 is packed.
        // Reading any of them as a depth would be a measured wrong answer.
        for name in ["nv12", "nv21", "rgb24", "bgr24", "rgb48le", "rgba64le", "yuyv422", "uyvy422", "y210le", "p010le", "monow", "", "   "] {
            assertEqual(PixelFormatBitDepth.bitsPerChannel(fromPixelFormat: name), nil, "\(name.isEmpty ? "empty" : name) should state no depth")
        }
        assertEqual(PixelFormatBitDepth.bitsPerChannel(fromPixelFormat: nil), nil, "nil should state no depth")
    }

    private static func testImplausibleTokensStateNoDepth() {
        // Whitelisted family, but the token is not a real video bit depth:
        // float formats and hypothetical junk stay unanswered.
        for name in ["gbrpf32le", "gbrapf32le", "yuv422p99le", "gray32"] {
            assertEqual(PixelFormatBitDepth.bitsPerChannel(fromPixelFormat: name), nil, "\(name) should state no depth")
        }
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            fatalError("\(message). Expected \(expected), got \(actual)")
        }
    }
}
