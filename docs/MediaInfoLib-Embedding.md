# MediaInfoLib Embedding Notes

This project is prepared to ship a prebuilt MediaInfoLib runtime inside the macOS app bundle.

## Expected input location

Put the vendor-provided dynamic library here before building a distributable app:

`AssetFox/Vendor/MediaInfoLib/libmediainfo.dylib`

An alternate versioned filename is also accepted:

`libmediainfo.0.dylib`

## Bundle layout

During the build, the project copies the dylib to:

`AssetFox.app/Contents/Frameworks/libmediainfo.dylib`

The bridge loads MediaInfoLib from the bundle-local `Frameworks` folder. It no longer relies on `/opt/homebrew/lib` or `/usr/local/lib`.

## Project changes

The minimum Xcode-side setup is:

- a shell script build phase that optionally copies `libmediainfo.dylib` into `${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}`
- codesigning of the copied dylib when code signing is enabled
- existing `@executable_path/../Frameworks` runpath support remains sufficient for the final app layout

## Current behavior when the dylib is absent

- the project still compiles
- the `Media Info` tab still works
- deep MediaInfoLib inspection is unavailable until the dylib is present in the vendor folder

This keeps the app shippable without introducing a hard build-time dependency on a globally installed library.

## Licensing and attribution

The project now carries an in-app `OpenSourceLicenses.txt` resource with:

- MediaInfoLib attribution
- the official MediaInfoLib source URL
- the BSD 2-Clause license text required for redistribution
