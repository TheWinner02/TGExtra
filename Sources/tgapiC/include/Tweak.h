#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int TGExtraRebindSymbol(const char *symbolName, void *replacement, void **original);
int TGExtraDynamicInterpose(void *replacee, void *replacement);

#ifdef __cplusplus
}
#endif
#ifdef __OBJC__
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface TGExtraManualReadTransport : NSObject
+ (void)registerService:(id)service transport:(id)transport;
+ (BOOL)isAuthorizedRequest:(id)request payload:(NSData *)payload;
+ (void)sendPayload:(NSData *)payload transport:(id)transport completion:(void (^)(NSString * _Nullable error))completion NS_SWIFT_NAME(send(_:transport:completion:));
+ (NSString *)textForKey:(NSString *)key NS_SWIFT_NAME(text(_:));
@end
NS_ASSUME_NONNULL_END
#endif
