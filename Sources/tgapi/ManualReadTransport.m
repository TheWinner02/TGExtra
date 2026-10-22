#import "Headers.h"
#import "UI/Headers.h"
#import <objc/runtime.h>
#import "ManualReadResponse.h"

@interface MTRequestMessageService : NSObject
- (void)addRequest:(MTRequest *)request;
- (void)removeRequestByInternalId:(id)internalId;
@end

static NSMapTable *TGExtraManualReadServices;
static char TGExtraManualReadPayloadKey;

@implementation TGExtraManualReadTransport

+ (NSString *)textForKey:(NSString *)key {
    return [TGExtraLocalization localizedStringForKey:key];
}

+ (void)registerService:(id)service transport:(id)transport {
    if (!service || !transport) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!TGExtraManualReadServices) TGExtraManualReadServices = [NSMapTable weakToWeakObjectsMapTable];
        // Exact MTProto identity, never a global last-used account/service.
        [TGExtraManualReadServices setObject:service forKey:transport];
    });
}

+ (BOOL)isAuthorizedRequest:(id)request payload:(NSData *)payload {
    NSData *approved = objc_getAssociatedObject(request, &TGExtraManualReadPayloadKey);
    if (!approved || ![approved isEqualToData:payload] || payload.length < 4) return NO;
    int32_t function = 0;
    [payload getBytes:&function length:4];
    return function == kMessagesReadHistory || function == -871347913 || function == kMessagesReadDiscussion;
}

+ (void)sendPayload:(NSData *)payload transport:(id)transport completion:(void (^)(NSString *))completion {
    NSAssert(NSThread.isMainThread, @"Manual read transport must run on main");
    MTRequestMessageService *service = [TGExtraManualReadServices objectForKey:transport];
    Class requestClass = NSClassFromString(@"MTRequest");
    if (!service || !requestClass || ![service respondsToSelector:@selector(addRequest:)]) {
        completion([self textForKey:@"MANUAL_READ_TRANSPORT_UNAVAILABLE"]);
        return;
    }
    MTRequest *request = [[requestClass alloc] init];
    uint32_t requestFunction = 0;
    if (payload.length >= 4) [payload getBytes:&requestFunction length:4];
    objc_setAssociatedObject(request, &TGExtraManualReadPayloadKey, [payload copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [request setPayload:payload metadata:@"TGExtra.manualRead" shortMetadata:@"manualRead"
        responseParser:^id(NSData *data) {
            return [TGExtraManualReadResponse decodeData:data requestFunction:requestFunction];
        }];
    request.needsTimeoutTimer = YES;
    __block BOOL finished = NO;
    void (^finish)(NSString *) = ^(NSString *error) {
        if (finished) return;
        finished = YES;
        completion(error);
    };
    request.completed = ^(id response, MTRequestResponseInfo *info, MTRpcError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *(^details)(NSString *, NSString *) = ^NSString *(NSString *key, NSString *diagnostic) {
                NSString *message = [NSString stringWithFormat:@"%@\n\n%@: %@", [self textForKey:key], [self textForKey:@"MANUAL_READ_DIAGNOSTIC"], diagnostic];
                NSLog(@"[TGExtra Manual Read] request %08x: %@", requestFunction, diagnostic);
                return message;
            };
            if (error) {
                NSString *diagnostic = [NSString stringWithFormat:@"RPC error class %@", NSStringFromClass([error class])];
                if ([error respondsToSelector:@selector(errorCode)]) diagnostic = [diagnostic stringByAppendingFormat:@", code %d", error.errorCode];
                finish(details(@"MANUAL_READ_SERVER_ERROR", diagnostic)); return;
            }
            TGExtraManualReadResponse *decoded = nil;
            if ([response isKindOfClass:TGExtraManualReadResponse.class]) decoded = response;
            else if ([response isKindOfClass:NSData.class]) decoded = [TGExtraManualReadResponse decodeData:response requestFunction:requestFunction];
            if (!decoded) {
                finish(details(@"MANUAL_READ_UNVERIFIED", [NSString stringWithFormat:@"unexpected result class %@", response ? NSStringFromClass([response class]) : @"nil"])); return;
            }
            NSLog(@"[TGExtra Manual Read] request %08x: %@", requestFunction, decoded.diagnostic);
            finish(decoded.accepted ? nil : details(@"MANUAL_READ_UNVERIFIED", decoded.diagnostic));
        });
    };
    __weak MTRequestMessageService *weakService = service;
    id internalId = request.internalId;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (finished) return;
        [weakService removeRequestByInternalId:internalId];
        finish([self textForKey:@"MANUAL_READ_TIMEOUT"]);
    });
    [service addRequest:request];
}
@end
