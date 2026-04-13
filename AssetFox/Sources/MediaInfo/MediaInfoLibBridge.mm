#import "MediaInfoLibBridge.h"

#include <dlfcn.h>
#include <cstring>
#include <string>
#include <vector>
#include <cwchar>

namespace {
using MediaInfo_New_Func = void *(*)(void);
using MediaInfo_Delete_Func = void (*)(void *);
using MediaInfo_Open_Func = size_t (*)(void *, const wchar_t *);
using MediaInfo_Close_Func = void (*)(void *);
using MediaInfo_Inform_Func = const wchar_t *(*)(void *, size_t);
using MediaInfo_Option_Func = const wchar_t *(*)(void *, const wchar_t *, const wchar_t *);

struct MediaInfoLibSymbols {
    void *libraryHandle = nullptr;
    MediaInfo_New_Func create = nullptr;
    MediaInfo_Delete_Func destroy = nullptr;
    MediaInfo_Open_Func open = nullptr;
    MediaInfo_Close_Func close = nullptr;
    MediaInfo_Inform_Func inform = nullptr;
    MediaInfo_Option_Func option = nullptr;
    bool attempted = false;
};

static MediaInfoLibSymbols &sharedSymbols() {
    static MediaInfoLibSymbols symbols;
    return symbols;
}

static NSArray<NSString *> *candidateLibraryPaths() {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *frameworksPath = NSBundle.mainBundle.privateFrameworksPath;

    if (frameworksPath.length > 0) {
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"libmediainfo.dylib"]];
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"libmediainfo.0.dylib"]];
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"MediaInfoLib/libmediainfo.dylib"]];
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"MediaInfoLib/libmediainfo.0.dylib"]];
    }

    return paths;
}

static NSString *stringFromWide(const wchar_t *input) {
    if (input == nullptr) {
        return nil;
    }

    size_t length = wcslen(input);
    if (length == 0) {
        return nil;
    }

    NSData *data = [NSData dataWithBytes:input length:length * sizeof(wchar_t)];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF32LittleEndianStringEncoding];
    return string.length > 0 ? string : nil;
}

static std::wstring wideFromString(NSString *input) {
    if (input.length == 0) {
        return std::wstring();
    }

    NSData *data = [input dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    if (data.length == 0) {
        return std::wstring();
    }

    std::wstring output(data.length / sizeof(wchar_t), L'\0');
    memcpy(output.data(), data.bytes, data.length);
    if (!output.empty() && output.back() == L'\0') {
        output.pop_back();
    }
    return output;
}

static BOOL ensureLibraryLoaded(NSMutableArray<NSString *> *errors) {
    MediaInfoLibSymbols &symbols = sharedSymbols();
    if (symbols.attempted) {
        return symbols.libraryHandle != nullptr;
    }

    symbols.attempted = true;

    for (NSString *path in candidateLibraryPaths()) {
        void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
        if (handle == nullptr) {
            continue;
        }

        symbols.create = reinterpret_cast<MediaInfo_New_Func>(dlsym(handle, "MediaInfo_New"));
        symbols.destroy = reinterpret_cast<MediaInfo_Delete_Func>(dlsym(handle, "MediaInfo_Delete"));
        symbols.open = reinterpret_cast<MediaInfo_Open_Func>(dlsym(handle, "MediaInfo_Open"));
        symbols.close = reinterpret_cast<MediaInfo_Close_Func>(dlsym(handle, "MediaInfo_Close"));
        symbols.inform = reinterpret_cast<MediaInfo_Inform_Func>(dlsym(handle, "MediaInfo_Inform"));
        symbols.option = reinterpret_cast<MediaInfo_Option_Func>(dlsym(handle, "MediaInfo_Option"));

        if (symbols.create != nullptr &&
            symbols.destroy != nullptr &&
            symbols.open != nullptr &&
            symbols.close != nullptr &&
            symbols.inform != nullptr &&
            symbols.option != nullptr) {
            symbols.libraryHandle = handle;
            return YES;
        }

        dlclose(handle);
    }

    [errors addObject:@"Embedded MediaInfoLib runtime was not found in the app bundle Frameworks folder."];
    return NO;
}
}

@implementation MediaInfoLibBridge

+ (NSDictionary<NSString *, id> *)inspectFileAtPath:(NSString *)path {
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    NSMutableArray<NSString *> *errors = [NSMutableArray array];

    if (path.length == 0) {
        [errors addObject:@"No file path was provided to MediaInfoLib."];
        return @{
            @"status": @"error",
            @"warnings": warnings,
            @"errors": errors
        };
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [errors addObject:@"The selected file does not exist anymore."];
        return @{
            @"status": @"error",
            @"warnings": warnings,
            @"errors": errors
        };
    }

    if (!ensureLibraryLoaded(errors)) {
        return @{
            @"status": @"libraryUnavailable",
            @"warnings": warnings,
            @"errors": errors
        };
    }

    MediaInfoLibSymbols &symbols = sharedSymbols();
    void *handle = symbols.create();
    if (handle == nullptr) {
        [errors addObject:@"MediaInfoLib failed to create an inspection handle."];
        return @{
            @"status": @"error",
            @"warnings": warnings,
            @"errors": errors
        };
    }

    const std::wstring outputOption = wideFromString(@"JSON");
    const std::wstring completeOption = wideFromString(@"1");
    const std::wstring filePath = wideFromString(path);

    symbols.option(handle, L"Output", outputOption.c_str());
    symbols.option(handle, L"Complete", completeOption.c_str());

    size_t openResult = symbols.open(handle, filePath.c_str());
    if (openResult == 0) {
        symbols.close(handle);
        symbols.destroy(handle);
        [errors addObject:@"MediaInfoLib could not open this file."];
        return @{
            @"status": @"error",
            @"warnings": warnings,
            @"errors": errors
        };
    }

    NSString *json = stringFromWide(symbols.inform(handle, 0));
    symbols.close(handle);
    symbols.destroy(handle);

    if (json.length == 0) {
        [errors addObject:@"MediaInfoLib returned no metadata payload for this file."];
        return @{
            @"status": @"error",
            @"warnings": warnings,
            @"errors": errors
        };
    }

    return @{
        @"status": @"success",
        @"json": json,
        @"warnings": warnings,
        @"errors": errors
    };
}

@end
