#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MediaInfoLibBridge : NSObject

+ (NSDictionary<NSString *, id> *)inspectFileAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END

