#import "../Headers.h"

static BOOL TGExtraIsChatController(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    return [name hasSuffix:@"ChatControllerImpl"] || [name hasSuffix:@"ChatController"];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (TGExtraIsChatController(self)) [TGExtraManualReadController updateForController:self];
}
- (void)viewDidLayoutSubviews {
    %orig;
    if (TGExtraIsChatController(self)) [TGExtraManualReadController updateForController:self];
}
- (void)viewWillDisappear:(BOOL)animated {
    if (TGExtraIsChatController(self)) [TGExtraManualReadController hideForController:self];
    %orig;
}
%end
