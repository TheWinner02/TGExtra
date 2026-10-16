#import "../Headers.h"
#import <objc/runtime.h>

static BOOL TGExtraIsChatController(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    return [name hasSuffix:@"ChatControllerImpl"] || [name hasSuffix:@"ChatController"];
}

%hook UIViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (TGExtraIsChatController(self)) [TGExtraManualReadController updateForController:self];
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (TGExtraIsChatController(self)) [TGExtraManualReadController updateForController:self];
}
- (void)viewWillDisappear:(BOOL)animated {
    if (TGExtraIsChatController(self)) [TGExtraManualReadController hideForController:self];
    %orig;
}
%end

// Merge before UIKit notifies the client's navigation bar. Re-inserting during
// layout is too late: the client repeatedly renders its own avatar-only list.
// Unmanaged navigation items pass through unchanged (including nil setters).
static char TGExtraManualReadRedirectKey;

%hook UINavigationItem
- (void)setRightBarButtonItem:(UIBarButtonItem *)item {
    // UIKit can delegate between the single/multiple animated setters. Let its
    // internal calls finish without redirecting back into the same setter.
    if (objc_getAssociatedObject(self, &TGExtraManualReadRedirectKey)) { %orig; return; }
    NSArray *merged = [TGExtraManualReadController rightItemsForNavigationItem:self proposedItems:item ? @[item] : @[]];
    if (merged) {
        objc_setAssociatedObject(self, &TGExtraManualReadRedirectKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try { [self setRightBarButtonItems:merged animated:NO]; }
        @finally { objc_setAssociatedObject(self, &TGExtraManualReadRedirectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        return;
    }
    %orig;
}
- (void)setRightBarButtonItem:(UIBarButtonItem *)item animated:(BOOL)animated {
    if (objc_getAssociatedObject(self, &TGExtraManualReadRedirectKey)) { %orig; return; }
    NSArray *merged = [TGExtraManualReadController rightItemsForNavigationItem:self proposedItems:item ? @[item] : @[]];
    if (merged) {
        objc_setAssociatedObject(self, &TGExtraManualReadRedirectKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try { [self setRightBarButtonItems:merged animated:animated]; }
        @finally { objc_setAssociatedObject(self, &TGExtraManualReadRedirectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        return;
    }
    %orig;
}
- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items {
    NSArray *merged = [TGExtraManualReadController rightItemsForNavigationItem:self proposedItems:items ?: @[]];
    %orig(merged ?: items);
}
- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items animated:(BOOL)animated {
    NSArray *merged = [TGExtraManualReadController rightItemsForNavigationItem:self proposedItems:items ?: @[]];
    %orig(merged ?: items, animated);
}
%end
