#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MediaInfoLibBridge : NSObject

+ (NSDictionary<NSString *, id> *)inspectFileAtPath:(NSString *)path;
+ (NSDictionary<NSString *, id> *)runtimeStatus;

@end

NS_ASSUME_NONNULL_END
