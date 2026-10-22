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

// Stage only managed chat items. The Swift coordinator coalesces native
// clear/set sequences and bypasses this hook while applying the final list.
%hook UINavigationItem
- (void)setRightBarButtonItem:(UIBarButtonItem *)item {
    if ([TGExtraManualReadController queueRightItemsForNavigationItem:self proposedItems:item ? @[item] : @[]]) return;
    %orig;
}
- (void)setRightBarButtonItem:(UIBarButtonItem *)item animated:(BOOL)animated {
    if ([TGExtraManualReadController queueRightItemsForNavigationItem:self proposedItems:item ? @[item] : @[]]) return;
    %orig;
}
- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items {
    if ([TGExtraManualReadController queueRightItemsForNavigationItem:self proposedItems:items ?: @[]]) return;
    %orig;
}
- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items animated:(BOOL)animated {
    if ([TGExtraManualReadController queueRightItemsForNavigationItem:self proposedItems:items ?: @[]]) return;
    %orig;
}
%end
