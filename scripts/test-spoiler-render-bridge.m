#import <UIKit/UIKit.h>
#import "../Sources/tgapiC/include/Tweak.h"
#include <assert.h>

@implementation UIView
- (instancetype)init {
    if ((self = [super init])) { _layer = [CALayer layer]; _bounds = CGRectMake(0, 0, 100, 20); }
    return self;
}
@end
@implementation UIImage
@end
@implementation UITapGestureRecognizer
- (CGPoint)locationInView:(UIView *)view { return CGPointZero; }
@end

@interface ASDisplayNode : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) NSUInteger draws;
- (void)recursivelyEnsureDisplaySynchronously:(BOOL)synchronously;
@end
@implementation ASDisplayNode
- (instancetype)init {
    if ((self = [super init])) { _view = [UIView new]; _alpha = 1.0; }
    return self;
}
- (void)recursivelyEnsureDisplaySynchronously:(BOOL)synchronously { assert(synchronously); self.draws++; }
@end

@interface FixtureInvisibleInkDustNode : ASDisplayNode
@property (nonatomic) NSUInteger taps;
- (void)tap:(UITapGestureRecognizer *)gesture;
@end
@implementation FixtureInvisibleInkDustNode
- (void)tap:(UITapGestureRecognizer *)gesture {
    assert(CGPointEqualToPoint([gesture locationInView:self.view], CGPointMake(50, 10)));
    self.taps++;
}
@end
@interface FixtureMediaDustNode : ASDisplayNode
- (void)tap:(UITapGestureRecognizer *)gesture;
@end
@implementation FixtureMediaDustNode
- (void)tap:(UITapGestureRecognizer *)gesture { }
@end

int main(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setBool:YES forKey:@"TGExtraRevealSpoilers"];
        ASDisplayNode *text = [ASDisplayNode new];
        ASDisplayNode *mask = [ASDisplayNode new];
        UIView *otherMask = [UIView new];
        assert(![TGExtraSpoilerGestureBridge shouldKeepTextVisible:text]);
        @autoreleasepool {
            FixtureInvisibleInkDustNode *dust = [FixtureInvisibleInkDustNode new];
            text.view.maskView = mask.view;
            assert([TGExtraSpoilerGestureBridge revealTextDust:dust content:text mask:mask]);
            assert(dust.taps == 1 && dust.alpha == 0.0 && text.view.maskView == nil);
            assert([TGExtraSpoilerGestureBridge shouldKeepTextVisible:text]);
            assert([TGExtraSpoilerGestureBridge shouldSkipMask:mask.view forView:text.view]);
            assert(![TGExtraSpoilerGestureBridge shouldSkipMask:otherMask forView:text.view]);
            assert(![TGExtraSpoilerGestureBridge shouldSkipMask:nil forView:text.view]);
            assert(![TGExtraSpoilerGestureBridge shouldKeepTextVisible:[ASDisplayNode new]]);
            text.alpha = 0.0;
            [TGExtraSpoilerGestureBridge finishTextDisplay:text restoreAlpha:YES ensureDisplay:YES];
            assert(text.alpha == 1.0 && text.draws == 1);
            // Repeated layout must not redraw a correct text node.
            for (NSUInteger i = 0; i < 100; i++) {
                [TGExtraSpoilerGestureBridge finishTextDisplay:text restoreAlpha:YES ensureDisplay:NO];
            }
            assert(text.draws == 1);
            // A cell update that resets alpha is repaired, even with the same
            // cached layout object, rather than being treated as already done.
            text.alpha = 0.0;
            [TGExtraSpoilerGestureBridge finishTextDisplay:text restoreAlpha:YES ensureDisplay:NO];
            assert(text.alpha == 1.0 && text.draws == 2);
            text.view.maskView = otherMask;
            assert([TGExtraSpoilerGestureBridge revealTextDust:dust content:text mask:mask]);
            assert(text.view.maskView == otherMask);
            assert(![TGExtraSpoilerGestureBridge revealTextDust:[FixtureMediaDustNode new] content:text mask:mask]);
            [defaults setBool:NO forKey:@"TGExtraRevealSpoilers"];
            assert(![TGExtraSpoilerGestureBridge shouldKeepTextVisible:text]);
            assert(![TGExtraSpoilerGestureBridge shouldSkipMask:mask.view forView:text.view]);
            [defaults setBool:YES forKey:@"TGExtraRevealSpoilers"];
        }
        // No stale ownership survives a recycled/deallocated dust node.
        assert(![TGExtraSpoilerGestureBridge shouldKeepTextVisible:text]);
        assert(![TGExtraSpoilerGestureBridge shouldSkipMask:mask.view forView:text.view]);
        [defaults removeObjectForKey:@"TGExtraRevealSpoilers"];
        puts("Spoiler text redraw, mask ownership, reuse and toggle checks passed");
    }
    return 0;
}
