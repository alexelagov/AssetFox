import Foundation

// CLI-only replacement for the app's Objective-C++ MediaInfoLibBridge.
// The app links MediaInfo_* symbols at build time and locates the dylib inside
// the app bundle Frameworks folder; the CLI has no app bundle, so it loads the
// vendored dylib with dlopen at runtime and exposes the same payload contract.
// Never add this file to the AssetFox app target: the type name intentionally
// matches the Objective-C bridge and the two must stay mutually exclusive.

enum MediaInfoLibBridge {
    static func inspectFile(atPath path: String) -> [String: Any] {
        let warnings: [String] = []
        var errors: [String] = []

        guard !path.isEmpty else {
            errors.append("No file path was provided to MediaInfoLib.")
            return ["status": "error", "warnings": warnings, "errors": errors]
        }

        guard FileManager.default.fileExists(atPath: path) else {
            errors.append("The selected file does not exist anymore.")
            return ["status": "error", "warnings": warnings, "errors": errors]
        }

        guard let runtime = MediaInfoLibRuntime.shared else {
            errors.append(contentsOf: MediaInfoLibRuntime.loadErrors)
            return ["status": "libraryUnavailable", "warnings": warnings, "errors": errors]
        }

        guard let handle = runtime.newHandle() else {
            errors.append("MediaInfoLib failed to create an inspection handle.")
            return ["status": "error", "warnings": warnings, "errors": errors]
        }
        defer { runtime.deleteHandle(handle) }

        runtime.setOption(handle, name: "Output", value: "JSON")
        runtime.setOption(handle, name: "Complete", value: "1")

        guard runtime.open(handle, path: path) else {
            errors.append("MediaInfoLib could not open this file.")
            return ["status": "error", "warnings": warnings, "errors": errors]
        }
        defer { runtime.close(handle) }

        guard let json = runtime.inform(handle), !json.isEmpty else {
            errors.append("MediaInfoLib returned no metadata payload for this file.")
            return ["status": "error", "warnings": warnings, "errors": errors]
        }

        return ["status": "success", "json": json, "warnings": warnings, "errors": errors]
    }

    static func runtimeStatus() -> [String: Any] {
        let runtime = MediaInfoLibRuntime.shared
        return [
            "bundled": runtime != nil,
            "loaded": runtime != nil,
            "path": runtime?.libraryPath ?? "",
            "errors": runtime == nil ? MediaInfoLibRuntime.loadErrors : []
        ]
    }
}

final class MediaInfoLibRuntime {
    private typealias NewFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias DeleteFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias OpenFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<Int32>?) -> UInt
    private typealias CloseFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias InformFn = @convention(c) (UnsafeMutableRawPointer?, UInt) -> UnsafePointer<Int32>?
    private typealias OptionFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<Int32>?, UnsafePointer<Int32>?) -> UnsafePointer<Int32>?

    static let shared: MediaInfoLibRuntime? = {
        for candidate in candidateLibraryPaths() where FileManager.default.fileExists(atPath: candidate) {
            if let runtime = MediaInfoLibRuntime(libraryPath: candidate) {
                return runtime
            }
        }
        return nil
    }()

    private static var recordedLoadErrors: [String] = []

    static var loadErrors: [String] {
        if recordedLoadErrors.isEmpty {
            return ["MediaInfoLib dylib was not found. Set ASSETFOX_MEDIAINFO_DYLIB or keep the resource bundle next to assetfox-cli."]
        }
        return recordedLoadErrors
    }

    let libraryPath: String
    private let newFn: NewFn
    private let deleteFn: DeleteFn
    private let openFn: OpenFn
    private let closeFn: CloseFn
    private let informFn: InformFn
    private let optionFn: OptionFn

    private init?(libraryPath: String) {
        guard let handle = dlopen(libraryPath, RTLD_NOW) else {
            let message = String(cString: dlerror())
            Self.recordedLoadErrors.append("dlopen failed for \(libraryPath): \(message)")
            return nil
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else {
                Self.recordedLoadErrors.append("Symbol \(name) is missing in \(libraryPath).")
                return nil
            }
            return unsafeBitCast(pointer, to: type)
        }

        guard let newFn = symbol("MediaInfo_New", as: NewFn.self),
              let deleteFn = symbol("MediaInfo_Delete", as: DeleteFn.self),
              let openFn = symbol("MediaInfo_Open", as: OpenFn.self),
              let closeFn = symbol("MediaInfo_Close", as: CloseFn.self),
              let informFn = symbol("MediaInfo_Inform", as: InformFn.self),
              let optionFn = symbol("MediaInfo_Option", as: OptionFn.self) else {
            dlclose(handle)
            return nil
        }

        self.libraryPath = libraryPath
        self.newFn = newFn
        self.deleteFn = deleteFn
        self.openFn = openFn
        self.closeFn = closeFn
        self.informFn = informFn
        self.optionFn = optionFn
    }

    private static func candidateLibraryPaths() -> [String] {
        var candidates: [String] = []

        if let override = ProcessInfo.processInfo.environment["ASSETFOX_MEDIAINFO_DYLIB"], !override.isEmpty {
            candidates.append(override)
        }

        if let bundled = Bundle.module.url(forResource: "libmediainfo.0", withExtension: "dylib") {
            candidates.append(bundled.path)
        }

        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for name in ["libmediainfo.0.dylib", "libmediainfo.dylib"] {
            candidates.append(executableDirectory.appendingPathComponent(name).path)
            candidates.append(executableDirectory.appendingPathComponent("Frameworks").appendingPathComponent(name).path)
        }

        for prefix in ["/opt/homebrew/lib", "/usr/local/lib"] {
            candidates.append("\(prefix)/libmediainfo.0.dylib")
            candidates.append("\(prefix)/libmediainfo.dylib")
        }

        return candidates
    }

    func newHandle() -> UnsafeMutableRawPointer? {
        newFn()
    }

    func deleteHandle(_ handle: UnsafeMutableRawPointer) {
        deleteFn(handle)
    }

    func setOption(_ handle: UnsafeMutableRawPointer, name: String, value: String) {
        let wideName = Self.wideCharacters(from: name)
        let wideValue = Self.wideCharacters(from: value)
        _ = wideName.withUnsafeBufferPointer { namePointer in
            wideValue.withUnsafeBufferPointer { valuePointer in
                optionFn(handle, namePointer.baseAddress, valuePointer.baseAddress)
            }
        }
    }

    func open(_ handle: UnsafeMutableRawPointer, path: String) -> Bool {
        let widePath = Self.wideCharacters(from: path)
        let result = widePath.withUnsafeBufferPointer { pathPointer in
            openFn(handle, pathPointer.baseAddress)
        }
        return result != 0
    }

    func close(_ handle: UnsafeMutableRawPointer) {
        closeFn(handle)
    }

    func inform(_ handle: UnsafeMutableRawPointer) -> String? {
        Self.string(fromWide: informFn(handle, 0))
    }

    private static func wideCharacters(from string: String) -> [Int32] {
        var characters = string.unicodeScalars.map { Int32(bitPattern: $0.value) }
        characters.append(0)
        return characters
    }

    private static func string(fromWide pointer: UnsafePointer<Int32>?) -> String? {
        guard let pointer else { return nil }

        var view = String.UnicodeScalarView()
        var index = 0
        while pointer[index] != 0 {
            if let scalar = Unicode.Scalar(UInt32(bitPattern: pointer[index])) {
                view.append(scalar)
            }
            index += 1
        }

        let result = String(view)
        return result.isEmpty ? nil : result
    }
}
