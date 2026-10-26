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

@interface TGExtraSpoilerTextState : NSObject
@property (nonatomic, weak) NSObject *dust;
@property (nonatomic, weak) UIView *mask;
@end
@implementation TGExtraSpoilerTextState
@end
static char TGExtraSpoilerTextStateKey;

static UIView *TGExtraSpoilerNodeView(NSObject *node) {
    Class displayNode = NSClassFromString(@"ASDisplayNode");
    SEL getter = NSSelectorFromString(@"view");
    if (!displayNode || ![node isKindOfClass:displayNode] || ![node respondsToSelector:getter]) return nil;
    return ((UIView *(*)(id, SEL))objc_msgSend)(node, getter);
}

@implementation TGExtraSpoilerGestureBridge
+ (BOOL)shouldKeepTextVisible:(NSObject *)node {
    TGExtraSpoilerTextState *state = objc_getAssociatedObject(node, &TGExtraSpoilerTextStateKey);
    return state.dust != nil && [[NSUserDefaults standardUserDefaults] boolForKey:@"TGExtraRevealSpoilers"];
}

+ (BOOL)shouldSkipMask:(NSObject *)mask forView:(NSObject *)view {
    TGExtraSpoilerTextState *state = objc_getAssociatedObject(view, &TGExtraSpoilerTextStateKey);
    return mask != nil && mask == state.mask && [self shouldKeepTextVisible:view];
}

+ (BOOL)revealTextDust:(NSObject *)dust content:(NSObject *)text mask:(NSObject *)mask {
    if (!NSThread.isMainThread || ![NSStringFromClass(dust.class) hasSuffix:@"InvisibleInkDustNode"]) return NO;
    UIView *view = TGExtraSpoilerNodeView(text);
    UIView *maskView = TGExtraSpoilerNodeView(mask);
    if (!view || !maskView) return NO;
    TGExtraSpoilerTextState *state = objc_getAssociatedObject(text, &TGExtraSpoilerTextStateKey);
    if (state.dust != dust || state.mask != maskView) {
        state = [TGExtraSpoilerTextState new];
        state.dust = dust;
        state.mask = maskView;
        objc_setAssociatedObject(text, &TGExtraSpoilerTextStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &TGExtraSpoilerTextStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![self revealDust:dust]) {
        objc_setAssociatedObject(text, &TGExtraSpoilerTextStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &TGExtraSpoilerTextStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return NO;
    }
    if (view.maskView == maskView) view.maskView = nil;
    // A native non-animated accessibility path may also install an opacity
    // animation. Remove it only from the text explicitly owned by this dust.
    [view.layer removeAnimationForKey:@"opacity"];
    SEL setAlpha = NSSelectorFromString(@"setAlpha:");
    if ([dust respondsToSelector:setAlpha]) ((void (*)(id, SEL, CGFloat))objc_msgSend)(dust, setAlpha, 0.0);
    return YES;
}

+ (void)finishTextDisplay:(NSObject *)node restoreAlpha:(BOOL)restoreAlpha ensureDisplay:(BOOL)ensureDisplay {
    if (!NSThread.isMainThread) return;
    Class displayNode = NSClassFromString(@"ASDisplayNode");
    if (!displayNode || ![node isKindOfClass:displayNode]) return;
    SEL setAlpha = NSSelectorFromString(@"setAlpha:");
    SEL syncSelector = NSSelectorFromString(@"recursivelyEnsureDisplaySynchronously:");
    SEL alpha = NSSelectorFromString(@"alpha");
    BOOL becameVisible = restoreAlpha && [node respondsToSelector:alpha] &&
        ((CGFloat (*)(id, SEL))objc_msgSend)(node, alpha) != 1.0;
    if (becameVisible && [node respondsToSelector:setAlpha]) {
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(node, setAlpha, 1.0);
    }
    // Scope synchronous drawing to the revealed text, never the full cell,
    // chat list or media subtree. Do not invalidate already correct contents.
    if ((ensureDisplay || becameVisible) && [node respondsToSelector:syncSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(node, syncSelector, YES);
    }
}

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
