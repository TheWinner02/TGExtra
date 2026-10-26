#import "SpoilerTextRendering.h"
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

// TelegramTextAttributes.Spoiler belongs to display formatting. The input
// editor and outgoing entity generator use Attribute__Spoiler, which MUST be
// preserved. Never remove a MessageTextEntity or mutate a Postbox message.
static NSString *const TGExtraDisplaySpoiler = @"TelegramSpoiler";

static BOOL TGExtraRevealDisplaySpoilers(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"TGExtraRevealSpoilers"];
}

static NSDictionary *TGExtraDisplayAttributes(NSDictionary *attributes) {
    if (!attributes[TGExtraDisplaySpoiler] || !TGExtraRevealDisplaySpoilers()) return attributes;
    NSMutableDictionary *copy = [attributes mutableCopy];
    [copy removeObjectForKey:TGExtraDisplaySpoiler];
    return copy;
}

static BOOL TGExtraValidAttributeRange(NSAttributedString *text, NSRange range) {
    return range.location <= text.length && range.length <= text.length - range.location;
}

static void TGExtraReplaceAttributeMethod(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
        method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    }
}

static void TGExtraHookAttributeClass(Class cls) {
    SEL single = @selector(addAttribute:value:range:);
    IMP addSingle = class_getMethodImplementation(cls, single);
    IMP singleReplacement = imp_implementationWithBlock(^(NSMutableAttributedString *text, NSString *name, id value, NSRange range) {
        if ([name isEqualToString:TGExtraDisplaySpoiler] && TGExtraRevealDisplaySpoilers() &&
            value && TGExtraValidAttributeRange(text, range)) return;
        ((void (*)(id, SEL, NSString *, id, NSRange))addSingle)(text, single, name, value, range);
    });
    TGExtraReplaceAttributeMethod(cls, single, singleReplacement);

    SEL multiple = @selector(addAttributes:range:);
    IMP addMultiple = class_getMethodImplementation(cls, multiple);
    IMP multipleReplacement = imp_implementationWithBlock(^(NSMutableAttributedString *text, NSDictionary *attributes, NSRange range) {
        ((void (*)(id, SEL, NSDictionary *, NSRange))addMultiple)(text, multiple,
            TGExtraDisplayAttributes(attributes), range);
    });
    TGExtraReplaceAttributeMethod(cls, multiple, multipleReplacement);

    SEL replace = @selector(setAttributes:range:);
    IMP setAttributes = class_getMethodImplementation(cls, replace);
    IMP replaceReplacement = imp_implementationWithBlock(^(NSMutableAttributedString *text, NSDictionary *attributes, NSRange range) {
        ((void (*)(id, SEL, NSDictionary *, NSRange))setAttributes)(text, replace,
            TGExtraDisplayAttributes(attributes), range);
    });
    TGExtraReplaceAttributeMethod(cls, replace, replaceReplacement);
}

void TGExtraInstallSpoilerTextRendering(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Foundation is a class cluster. Probe the actual concrete mutable
        // classes rather than assuming a private class name or only hooking an
        // abstract base implementation that subclasses can bypass.
        NSMutableAttributedString *native = [[NSMutableAttributedString alloc] initWithString:@""];
        NSMutableAttributedString *bridged = CFBridgingRelease(CFAttributedStringCreateMutable(kCFAllocatorDefault, 0));
        Class classes[] = {object_getClass(native), object_getClass(bridged), NSMutableAttributedString.class};
        for (NSUInteger i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
            BOOL duplicate = NO;
            for (NSUInteger j = 0; j < i; j++) if (classes[j] == classes[i]) duplicate = YES;
            if (!duplicate && classes[i]) TGExtraHookAttributeClass(classes[i]);
        }
    });
}

__attribute__((constructor)) static void TGExtraLoadSpoilerTextRendering(void) {
    @autoreleasepool { TGExtraInstallSpoilerTextRendering(); }
}
