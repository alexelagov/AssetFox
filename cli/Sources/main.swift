import Foundation

let usage = """
assetfox-cli \(CLIOutput.cliVersion) - headless AssetFox media checks

Usage:
  assetfox-cli inspect [--pretty] <file>...
      Emit a JSON file passport per input (metadata via MediaInfoLib,
      AVFoundation, ImageIO, ffprobe fallback).

  assetfox-cli qc [--reference <file>] [--tolerance-frames N] [--include-raw] [--pretty] <file>...
      Run ffmpeg quality checks (black frames, freezes, reference cut
      comparison) and emit JSON findings. Default tolerance: 2 frames.

  assetfox-cli doctor [--pretty]
      Report runtime availability (MediaInfoLib dylib, ffmpeg, ffprobe).

Output is a single JSON object on stdout; progress lines go to stderr.
Environment: ASSETFOX_MEDIAINFO_DYLIB overrides the MediaInfoLib dylib path.
"""

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    print(usage)
    exit(2)
}

do {
    switch command {
    case "inspect":
        let parsed = try CLIInspectCommand.parse(arguments: Array(arguments.dropFirst()))
        try await parsed.run()
    case "qc":
        let parsed = try CLIQualityCheckCommand.parse(arguments: Array(arguments.dropFirst()))
        try await parsed.run()
    case "doctor":
        let parsed = try CLIDoctorCommand.parse(arguments: Array(arguments.dropFirst()))
        try parsed.run()
    case "--help", "-h", "help":
        print(usage)
    default:
        CLIOutput.fail("Unknown command: \(command)")
        print(usage)
        exit(2)
    }
} catch let error as CLIUsageError {
    CLIOutput.fail(error.message)
    exit(2)
} catch {
    CLIOutput.fail(error.localizedDescription)
    exit(1)
}
