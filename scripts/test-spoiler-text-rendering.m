#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../Sources/tgapi/SpoilerTextRendering.h"
#include <assert.h>

static NSString *const displaySpoiler = @"TelegramSpoiler";
static NSString *const inputSpoiler = @"Attribute__Spoiler";

static void assertDisplayText(NSAttributedString *text) {
    assert([text.string isEqualToString:@"Test"]);
    assert([text attribute:displaySpoiler atIndex:0 effectiveRange:NULL] == nil);
    assert([[text attribute:inputSpoiler atIndex:0 effectiveRange:NULL] boolValue]);
    assert([[text attribute:@"NSFont" atIndex:0 effectiveRange:NULL] isEqual:@"fixture-font"]);
    assert([[text attribute:@"TelegramTextUrl" atIndex:0 effectiveRange:NULL] isEqual:@"https://example.com"]);
}

int main(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id previous = [defaults objectForKey:@"TGExtraRevealSpoilers"];
        TGExtraInstallSpoilerTextRendering();
        TGExtraInstallSpoilerTextRendering();
        NSDictionary *source = @{displaySpoiler: @YES, inputSpoiler: @YES,
            @"NSFont": @"fixture-font", @"TelegramTextUrl": @"https://example.com"};
        [defaults setBool:NO forKey:@"TGExtraRevealSpoilers"];
        NSMutableAttributedString *original = [[NSMutableAttributedString alloc] initWithString:@"Test"];
        [original addAttributes:source range:NSMakeRange(0, 4)];
        assert([[original attribute:displaySpoiler atIndex:0 effectiveRange:NULL] boolValue]);
        [defaults setBool:YES forKey:@"TGExtraRevealSpoilers"];
        // Presentation filtering must not mutate a source dictionary or a
        // previously created model/input string, even across account switches.
        assert([source[displaySpoiler] boolValue]);
        assert([[original attribute:displaySpoiler atIndex:0 effectiveRange:NULL] boolValue]);
        for (NSUInteger i = 0; i < 100; i++) {
            NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:@"Test"];
            [text addAttributes:source range:NSMakeRange(0, 4)];
            assertDisplayText(text);
            [text setAttributes:source range:NSMakeRange(0, 4)];
            assertDisplayText(text);
            [text addAttribute:displaySpoiler value:@YES range:NSMakeRange(0, 4)];
            assertDisplayText(text);
            NSAttributedString *snapshot = [text copy];
            assertDisplayText(snapshot);
        }
        NSMutableAttributedString *bridged = CFBridgingRelease(CFAttributedStringCreateMutable(kCFAllocatorDefault, 0));
        [bridged replaceCharactersInRange:NSMakeRange(0, 0) withString:@"Test"];
        [bridged addAttributes:source range:NSMakeRange(0, 4)];
        assertDisplayText(bridged);
        [bridged setAttributes:nil range:NSMakeRange(0, 4)];
        assert([bridged attributesAtIndex:0 effectiveRange:NULL].count == 0);
        // Preserve normal Foundation validation rather than silently accepting
        // an invalid range just because it mentions a display spoiler.
        BOOL rejected = NO;
        @try { [bridged addAttribute:displaySpoiler value:@YES range:NSMakeRange(100, 1)]; }
        @catch (NSException *exception) { rejected = YES; }
        assert(rejected);
        dispatch_apply(100, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
            @autoreleasepool {
                NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:@"Test"];
                [text addAttributes:source range:NSMakeRange(0, 4)];
                assertDisplayText(text);
            }
        });
        [defaults setBool:NO forKey:@"TGExtraRevealSpoilers"];
        NSMutableAttributedString *disabled = [[NSMutableAttributedString alloc] initWithString:@"Test"];
        [disabled addAttribute:displaySpoiler value:@YES range:NSMakeRange(0, 4)];
        assert([[disabled attribute:displaySpoiler atIndex:0 effectiveRange:NULL] boolValue]);
        assert([source[displaySpoiler] boolValue]);
        if (previous) [defaults setObject:previous forKey:@"TGExtraRevealSpoilers"];
        else [defaults removeObjectForKey:@"TGExtraRevealSpoilers"];
        puts("Spoiler display formatting, input preservation, class clusters and parallel rendering passed");
    }
    return 0;
}
