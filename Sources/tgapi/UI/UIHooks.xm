#import <UIKit/UIKit.h>
#import "Headers.h"
#import "../Logger/Logger.h"

// Menu Open
@interface ASDisplayNode : NSObject
@property (atomic, assign, readonly) UIView *view;
@property (atomic, copy, readonly) NSArray *subnodes;
@property (atomic, copy, readwrite) NSString *accessibilityLabel;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
- (void)__handleSettingsTabLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)__handle5PleTap;
@end

@interface ASControlNode : ASDisplayNode
- (void)sendActionsForControlEvents:(NSUInteger)controlEvents withEvent:(UIEvent *)event;
@end

// Telegram has used both of these class names across recent builds.
%hook _TtC10TelegramUI29ChatPresentationInterfaceState
- (BOOL)copyProtectionEnabled {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableForwardRestriction]) return NO;
    return %orig;
}
%end

%hook _TtC30ChatPresentationInterfaceState30ChatPresentationInterfaceState
- (BOOL)copyProtectionEnabled {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableForwardRestriction]) return NO;
    return %orig;
}
%end

%hook _TtC7Postbox7Message
- (BOOL)isCopyProtected {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableForwardRestriction]) return NO;
    return %orig;
}
- (id)adAttribute {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableAllAds]) return nil;
    return %orig;
}
%end

%hook ChatMessageItem
- (BOOL)noForwards {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableForwardRestriction]) return NO;
    return %orig;
}
%end

%hook ApiChat
- (BOOL)noForwards {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableForwardRestriction]) return NO;
    return %orig;
}
%end

static ThreeFingerGestureHandler *gestureHandler = nil;
static __weak TGLocalization *TGLocalizationShared = nil;

%hook TGLocalization

- (id)initWithVersion:(int)a code:(id)b dict:(id)c isActive:(BOOL)d {
    TGLocalization *instance = %orig;
    if (a != 96929692 && instance) {
        TGLocalizationShared = instance;
    }
    return instance;
}

%end

void showUI() {
	TGExtra *ui = [TGExtra new];
	UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:ui];

	UIWindow *window = UIApplication.sharedApplication.keyWindow;
	UIViewController *rootVC = window.rootViewController;
	if (rootVC) {
	    [rootVC presentViewController:navVC animated:YES completion:nil];
	}
}

void handleThreeFingerLongPress(UILongPressGestureRecognizer *gesture) {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        showUI();
    }
}

@implementation ThreeFingerGestureHandler
- (void)handleThreeFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    handleThreeFingerLongPress(gesture);
}
@end

%hook ASDisplayNode
%property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
%property (nonatomic, strong) UITapGestureRecognizer *tapGesture;

%new
- (void)__handleSettingsTabLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
		showUI();
    }
}

%new
- (void)__handle5PleTap {
	showUI();
}

- (void)layout {
    %orig;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kDisableAllAds]) return;

    @try {
        NSString *className = NSStringFromClass([self class]);
        if ([className containsString:@"ChatSponsoredMessage"] ||
            [className containsString:@"ChatChannelAdItemNode"]) {
            self.view.hidden = YES;
            self.view.alpha = 0.0;
        }
    } @catch (NSException *exception) {
        customLog2(@"TGExtra ad UI hook exception: %@", exception);
    }
}

%end

%hook ASControlNode

- (void)sendActionsForControlEvents:(NSUInteger)controlEvents withEvent:(UIEvent *)event {
    if (controlEvents == (1 << 4) &&
        [[NSUserDefaults standardUserDefaults] boolForKey:kConfirmCalls]) {
        NSString *label = [(id)self accessibilityLabel];
        NSString *lower = label.lowercaseString;
        NSSet *audioLabels = [NSSet setWithArray:@[
            @"call", @"phone", @"chiama", @"chiamata", @"appel",
            @"llamar", @"anrufen", @"позвонить", @"звонок"
        ]];
        NSSet *videoLabels = [NSSet setWithArray:@[
            @"video", @"video call", @"videochiamata", @"appel vidéo",
            @"videollamada", @"videoanruf", @"видео", @"видеозвонок"
        ]];
        BOOL isAudio = lower.length > 0 && [audioLabels containsObject:lower];
        BOOL isVideo = lower.length > 0 && [videoLabels containsObject:lower];

        if (isAudio || isVideo) {
            UIWindow *window = UIApplication.sharedApplication.keyWindow;
            UIViewController *controller = window.rootViewController;
            while (controller.presentedViewController) {
                controller = controller.presentedViewController;
            }

            if (controller) {
                NSString *title = isVideo ? @"Avviare la videochiamata?" : @"Avviare la chiamata?";
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:title
                                     message:nil
                              preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Annulla"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Chiama"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(__unused UIAlertAction *action) {
                    %orig(controlEvents, event);
                }]];
                [controller presentViewController:alert animated:YES completion:nil];
                return;
            }
        }
    }
    %orig;
}

%end

%hook TabBarNode

- (void)didEnterHierarchy {
	%orig;

	ASDisplayNode *mainNode = self;

    for (ASDisplayNode *child in mainNode.subnodes) {
		NSString *localizedTitle = @"Chats";

		NSString *resultTitle = [TGLocalizationShared get:@"DialogList.TabTitle"];
		if (resultTitle.length > 0 && ![resultTitle isEqualToString:@"DialogList.TabTitle"]) {
			localizedTitle = resultTitle;
		}

        if ([child.accessibilityLabel isEqualToString:localizedTitle]) {

			if (!child.tapGesture) {
				child.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:child action:@selector(__handle5PleTap)];
				child.tapGesture.numberOfTapsRequired = 5;
			}

			if (![child.view.gestureRecognizers containsObject:child.tapGesture]) {
                [child.view addGestureRecognizer:child.tapGesture];
			}
        }
    }
}

%end

%hook PeerInfoScreenItemNode

- (void)didEnterHierarchy {
    %orig;

    ASDisplayNode *mainNode = self;

	if (!mainNode.longPressGesture) {
		 mainNode.longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:mainNode action:@selector(__handleSettingsTabLongPress:)];
	}

    // Check children for specific node
    for (ASDisplayNode *child in mainNode.subnodes) {
        if ([NSStringFromClass([child class]) isEqualToString:@"Display.AccessibilityAreaNode"]) {
			NSString *localizedTitle = @"Telegram Features";

			NSString *resultTitle = [TGLocalizationShared get:@"Settings.Support"];
			if (resultTitle.length > 0 && ![resultTitle isEqualToString:@"Settings.Support"]) {
				localizedTitle = resultTitle;
			}

            if ([child.accessibilityLabel isEqualToString:localizedTitle]) {

				if (![mainNode.view.gestureRecognizers containsObject:mainNode.longPressGesture]) {
					[mainNode.view addGestureRecognizer:mainNode.longPressGesture];
				}
            }
        }
    }
}

%end

__attribute__((constructor))
static void hook() {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
	 	%init(
		    TabBarNode = objc_getClass("TabBarUI.TabBarNode"),
            PeerInfoScreenItemNode = objc_getClass("PeerInfoScreen.PeerInfoScreenItemNode"),
            ChatMessageItem = objc_getClass("_TtC10TelegramUI15ChatMessageItem"),
            ApiChat = objc_getClass("_TtC10TelegramUI11ApiChat"),
            ASControlNode = objc_getClass("ASControlNode"),
            _TtC7Postbox7Message = objc_getClass("_TtC7Postbox7Message"),
            _TtC10TelegramUI29ChatPresentationInterfaceState = objc_getClass("_TtC10TelegramUI29ChatPresentationInterfaceState"),
            _TtC30ChatPresentationInterfaceState30ChatPresentationInterfaceState = objc_getClass("_TtC30ChatPresentationInterfaceState30ChatPresentationInterfaceState")
		);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *window = UIApplication.sharedApplication.keyWindow;
            if (window) {
                if (!gestureHandler) {
                    gestureHandler = [[ThreeFingerGestureHandler alloc] init];
                }

                UILongPressGestureRecognizer *threeFingerLongPress = [[UILongPressGestureRecognizer alloc]
                    initWithTarget:gestureHandler
                    action:@selector(handleThreeFingerLongPress:)];
                threeFingerLongPress.numberOfTouchesRequired = 3;
                threeFingerLongPress.minimumPressDuration = 0.5;

                [window addGestureRecognizer:threeFingerLongPress];
            }
        });
	});
}
