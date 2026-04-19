#import "MediaInfoLibBridge.h"

#include <string>
#include <cwchar>

extern "C" {
void *MediaInfo_New(void);
void MediaInfo_Delete(void *);
size_t MediaInfo_Open(void *, const wchar_t *);
void MediaInfo_Close(void *);
const wchar_t *MediaInfo_Inform(void *, size_t);
const wchar_t *MediaInfo_Option(void *, const wchar_t *, const wchar_t *);
}

namespace {
static NSLock *runtimeLock() {
    static NSLock *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSLock new];
    });
    return lock;
}

static NSString *runtimeLoadError = nil;

static NSArray<NSString *> *candidateLibraryPaths() {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *frameworksPath = NSBundle.mainBundle.privateFrameworksPath;
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;

    if (frameworksPath.length > 0) {
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"libmediainfo.dylib"]];
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"libmediainfo.0.dylib"]];
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"MediaInfoLib/libmediainfo.dylib"]];
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"MediaInfoLib/libmediainfo.0.dylib"]];
    }

    if (bundlePath.length > 0) {
        NSString *contentsFrameworks = [bundlePath stringByAppendingPathComponent:@"Contents/Frameworks"];
        [paths addObject:[contentsFrameworks stringByAppendingPathComponent:@"libmediainfo.dylib"]];
        [paths addObject:[contentsFrameworks stringByAppendingPathComponent:@"libmediainfo.0.dylib"]];
    }

    return paths;
}

static BOOL bundledRuntimeExists(void) {
    for (NSString *path in candidateLibraryPaths()) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }
    return NO;
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

static void setRuntimeLoadError(NSString *error) {
    NSLock *lock = runtimeLock();
    [lock lock];
    @try {
        runtimeLoadError = error.length > 0 ? [error copy] : nil;
    } @finally {
        [lock unlock];
    }
}

static NSString *currentRuntimeLoadError(void) {
    NSLock *lock = runtimeLock();
    [lock lock];
    @try {
        return runtimeLoadError;
    } @finally {
        [lock unlock];
    }
}

static BOOL canCreateHandle(NSMutableArray<NSString *> *errors) {
    if (!bundledRuntimeExists()) {
        NSString *message = @"Embedded MediaInfoLib runtime was not found in the app bundle Frameworks folder.";
        setRuntimeLoadError(message);
        [errors addObject:message];
        return NO;
    }

    void *handle = MediaInfo_New();
    if (handle == nullptr) {
        NSString *message = @"MediaInfoLib is bundled, but the runtime did not create an inspection handle.";
        setRuntimeLoadError(message);
        [errors addObject:message];
        return NO;
    }

    MediaInfo_Delete(handle);
    setRuntimeLoadError(nil);
    return YES;
}
}

@implementation MediaInfoLibBridge

+ (NSDictionary<NSString *, id> *)runtimeStatus {
    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    BOOL bundled = bundledRuntimeExists();
    BOOL loaded = canCreateHandle(errors);

    NSString *lastError = currentRuntimeLoadError();
    if (!loaded && errors.count == 0 && lastError.length > 0) {
        [errors addObject:lastError];
    }

    return @{
        @"bundled": @(bundled),
        @"loaded": @(loaded),
        @"errors": errors
    };
}

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

    if (!canCreateHandle(errors)) {
        return @{
            @"status": @"libraryUnavailable",
            @"warnings": warnings,
            @"errors": errors
        };
    }

    void *handle = MediaInfo_New();
    if (handle == nullptr) {
        NSString *message = @"MediaInfoLib failed to create an inspection handle.";
        setRuntimeLoadError(message);
        [errors addObject:message];
        return @{
            @"status": @"error",
            @"warnings": warnings,
            @"errors": errors
        };
    }

    const std::wstring outputOption = wideFromString(@"JSON");
    const std::wstring completeOption = wideFromString(@"1");
    const std::wstring filePath = wideFromString(path);

    MediaInfo_Option(handle, L"Output", outputOption.c_str());
    MediaInfo_Option(handle, L"Complete", completeOption.c_str());

    size_t openResult = MediaInfo_Open(handle, filePath.c_str());
    if (openResult == 0) {
        MediaInfo_Close(handle);
        MediaInfo_Delete(handle);
        [errors addObject:@"MediaInfoLib could not open this file."];
        return @{
            @"status": @"error",
            @"warnings": warnings,
            @"errors": errors
        };
    }

    NSString *json = stringFromWide(MediaInfo_Inform(handle, 0));
    MediaInfo_Close(handle);
    MediaInfo_Delete(handle);

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
