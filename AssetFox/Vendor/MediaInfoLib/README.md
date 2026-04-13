# Embedded MediaInfoLib Runtime

Place the prebuilt MediaInfoLib dynamic library in this folder when preparing a distributable build.

Expected filenames:

- `libmediainfo.dylib`
- `libmediainfo.0.dylib`

Build behavior:

- The Xcode target includes an optional build phase that looks in this folder.
- If a dylib is present, it is copied into `AssetFox.app/Contents/Frameworks/libmediainfo.dylib`.
- If no dylib is present, the build continues and `Media Info` falls back to the native AVFoundation/ImageIO path.

Runtime behavior:

- `MediaInfoLibBridge` now looks for MediaInfoLib only inside the app bundle `Frameworks` folder.
- The final architecture does not depend on Homebrew or any globally installed runtime.
