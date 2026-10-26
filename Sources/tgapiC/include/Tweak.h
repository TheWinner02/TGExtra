#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int TGExtraRebindSymbol(const char * _Nonnull symbolName, void * _Nonnull replacement, void * _Nullable * _Nullable original);
int TGExtraDynamicInterpose(void * _Nonnull replacee, void * _Nonnull replacement);

#ifdef __cplusplus
}
#endif
#ifdef __OBJC__
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface TGExtraSpoilerGestureBridge : NSObject
+ (BOOL)revealDust:(NSObject *)dust NS_SWIFT_NAME(revealDust(_:));
+ (BOOL)hasNoImage:(NSObject *)node NS_SWIFT_NAME(hasNoImage(_:));
+ (void)finishTextDisplay:(NSObject *)node restoreAlpha:(BOOL)restoreAlpha ensureDisplay:(BOOL)ensureDisplay NS_SWIFT_NAME(finishTextDisplay(_:restoreAlpha:ensureDisplay:));
+ (BOOL)revealTextDust:(NSObject *)dust content:(NSObject *)text mask:(NSObject *)mask NS_SWIFT_NAME(revealTextDust(_:content:mask:));
+ (BOOL)shouldKeepTextVisible:(NSObject *)node;
+ (BOOL)shouldSkipMask:(nullable NSObject *)mask forView:(NSObject *)view;
@end
@interface TGExtraManualReadTransport : NSObject
+ (void)registerService:(id)service transport:(id)transport;
+ (BOOL)isAuthorizedRequest:(id)request payload:(NSData *)payload;
+ (void)sendPayload:(NSData *)payload transport:(id)transport completion:(void (^)(NSString * _Nullable error))completion NS_SWIFT_NAME(send(_:transport:completion:));
+ (NSString *)textForKey:(NSString *)key NS_SWIFT_NAME(text(_:));
@end
NS_ASSUME_NONNULL_END
#endif
