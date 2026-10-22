#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface TGExtraManualReadResponse : NSObject
@property (nonatomic, readonly) BOOL accepted;
@property (nonatomic, copy, readonly) NSString *diagnostic;
+ (instancetype)decodeData:(NSData *)data requestFunction:(uint32_t)function;
@end
NS_ASSUME_NONNULL_END
