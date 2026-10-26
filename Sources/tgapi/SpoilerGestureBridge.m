#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>
#import "../tgapiC/include/Tweak.h"

// A local recognizer supplies a valid location to the dust node's ObjC action.
// No touches are dispatched to the chat, gallery, download or paywall buttons.
@interface TGExtraSpoilerRevealGesture : UITapGestureRecognizer
@end
@implementation TGExtraSpoilerRevealGesture
- (CGPoint)locationInView:(UIView *)view {
    return CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds));
}
@end

@implementation TGExtraSpoilerGestureBridge
+ (BOOL)hasNoImage:(NSObject *)node {
    Class imageNode = NSClassFromString(@"ASImageNode");
    SEL getter = NSSelectorFromString(@"image");
    if (!NSThread.isMainThread || !imageNode || ![node isKindOfClass:imageNode] ||
        ![node respondsToSelector:getter]) return NO;
    return ((id (*)(id, SEL))objc_msgSend)(node, getter) == nil;
}

+ (BOOL)revealDust:(NSObject *)dust {
    if (!NSThread.isMainThread) return NO;
    NSString *name = NSStringFromClass(dust.class);
    if (![name hasSuffix:@"InvisibleInkDustNode"] && ![name hasSuffix:@"MediaDustNode"]) return NO;
    SEL action = NSSelectorFromString(@"tap:");
    Method method = class_getInstanceMethod(dust.class, action);
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char returnType[16] = {0}, argumentType[128] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    method_getArgumentType(method, 2, argumentType, sizeof(argumentType));
    if (strcmp(returnType, @encode(void)) != 0 || argumentType[0] != '@') return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(dust, action, [TGExtraSpoilerRevealGesture new]);
    return YES;
}
@end
