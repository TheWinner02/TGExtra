#import <UIKit/UIKit.h>
#import "Headers.h"
#import "../Headers.h"
#import "../Logger/Logger.h"

#define kMessageDeletedNotification @"TGExtraMessageDeletedRealtime"
#define kAutomaticScheduleDidEnqueueNotification @"TGExtraAutomaticScheduleDidEnqueue"
#define kDeletedMessageIconTag 8898

// Menu Open
@interface ASDisplayNode : NSObject
@property (atomic, assign, readonly) UIView *view;
@property (atomic, copy, readonly) NSArray *subnodes;
@property (atomic, copy, readwrite) NSString *accessibilityLabel;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
- (void)__handleSettingsTabLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)__handle5PleTap;
- (void)setNeedsLayout;
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

static NSHashTable<ASDisplayNode *> *TGExtraActiveMessageNodes = nil;

static void TGExtraEnsureActiveMessageNodes(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        TGExtraActiveMessageNodes = [NSHashTable weakObjectsHashTable];
    });
}

static ASDisplayNode *TGExtraFindNodeByClassNamePrefix(ASDisplayNode *node, NSString *prefix) {
    if (!node) return nil;
    if ([NSStringFromClass([node class]) containsString:prefix]) return node;

    for (ASDisplayNode *child in node.subnodes) {
        ASDisplayNode *result = TGExtraFindNodeByClassNamePrefix(child, prefix);
        if (result) return result;
    }
    return nil;
}

static UIView *TGExtraFindFirstResponder(UIView *view) {
    if (view.isFirstResponder) return view;
    for (UIView *subview in view.subviews) {
        UIView *result = TGExtraFindFirstResponder(subview);
        if (result) return result;
    }
    return nil;
}

static BOOL TGExtraIsMediaComposerController(UIViewController *controller) {
    if (!controller) return NO;
    NSString *className = NSStringFromClass([controller class]);
    NSArray<NSString *> *markers = @[
        @"AttachmentController",
        @"AttachmentFileController",
        @"MediaPicker",
        @"MediaEditor",
        @"GalleryController"
    ];
    for (NSString *marker in markers) {
        if ([className containsString:marker]) return YES;
    }

    if ([controller isKindOfClass:[UINavigationController class]]) {
        return TGExtraIsMediaComposerController(
            ((UINavigationController *)controller).topViewController
        );
    }
    return NO;
}

static void TGExtraFinishAutomaticScheduleUI(void) {
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (!window) return;

    UIView *responder = TGExtraFindFirstResponder(window);
    if ([responder isKindOfClass:[UITextView class]]) {
        UITextView *textView = (UITextView *)responder;
        UITextPosition *start = textView.beginningOfDocument;
        UITextPosition *end = textView.endOfDocument;
        UITextRange *range = [textView textRangeFromPosition:start toPosition:end];
        if (range) [textView replaceRange:range withText:@""];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:UITextViewTextDidChangeNotification
                          object:textView];
        id<UITextViewDelegate> delegate = textView.delegate;
        if ([delegate respondsToSelector:@selector(textViewDidChange:)]) {
            [delegate textViewDidChange:textView];
        }
    } else if ([responder isKindOfClass:[UITextField class]]) {
        UITextField *textField = (UITextField *)responder;
        textField.text = @"";
        [textField sendActionsForControlEvents:UIControlEventEditingChanged];
    }

    UIViewController *controller = window.rootViewController;
    UIViewController *mediaController = nil;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
        if (TGExtraIsMediaComposerController(controller)) {
            mediaController = controller;
        }
    }
    if (mediaController) {
        [mediaController dismissViewControllerAnimated:YES completion:nil];
    }
}

@interface TGExtraAntiRevokeUpdater : NSObject
+ (instancetype)shared;
@end

@implementation TGExtraAntiRevokeUpdater

+ (instancetype)shared {
    static TGExtraAntiRevokeUpdater *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [TGExtraAntiRevokeUpdater new];
        TGExtraEnsureActiveMessageNodes();
        [[NSNotificationCenter defaultCenter] addObserver:instance
                                                 selector:@selector(handleDeleted:)
                                                     name:kMessageDeletedNotification
                                                   object:nil];
    });
    return instance;
}

- (void)handleDeleted:(NSNotification *)notification {
    NSArray<NSNumber *> *deletedIds = notification.userInfo[@"ids"];
    if (deletedIds.count == 0) return;
    [TLParser rememberDeletedMessageIds:deletedIds];

    NSHashTable<ASDisplayNode *> *nodes = nil;
    @synchronized (TGExtraActiveMessageNodes) {
        nodes = [TGExtraActiveMessageNodes copy];
    }

    for (ASDisplayNode *node in nodes) {
        NSNumber *messageId = [TLParser getMessageIdFromNode:node];
        if (messageId && [deletedIds containsObject:messageId]) {
            [node setNeedsLayout];
            [node.view setNeedsLayout];
        }
    }
}

@end

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

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableAllAds]) {
        @try {
            NSString *className = NSStringFromClass([self class]);
            if ([className containsString:@"ChatSponsoredMessage"] ||
                [className containsString:@"ChatChannelAdItemNode"]) {
                self.view.hidden = YES;
                self.view.alpha = 0.0;
                return;
            }
        } @catch (NSException *exception) {
            customLog2(@"TGExtra ad UI hook exception: %@", exception);
        }
    }

    NSString *className = NSStringFromClass([self class]);
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kHideStories] &&
        ([className containsString:@"StoryPeerList"] ||
         [className containsString:@"StoryContainer"] ||
         [className containsString:@"StorySetIndicator"] ||
         [className containsString:@"AvatarStoryIndicator"])) {
        self.view.hidden = YES;
        self.view.alpha = 0.0;
        return;
    }

    if (![className containsString:@"ChatMessage"] ||
        ![className containsString:@"ItemNode"]) {
        return;
    }

    TGExtraEnsureActiveMessageNodes();
    [TGExtraDeletedMessageCleaner registerNode:self];
    @synchronized (TGExtraActiveMessageNodes) {
        [TGExtraActiveMessageNodes addObject:self];
    }

    NSNumber *messageId = [TLParser getMessageIdFromNode:self];
    BOOL isDeleted = messageId && [TLParser isDeleted:messageId];
    UIImageView *icon = (UIImageView *)[self.view viewWithTag:kDeletedMessageIconTag];

    if (!isDeleted) {
        icon.hidden = YES;
        return;
    }

    if (!icon) {
        icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"trash.fill"]];
        icon.tag = kDeletedMessageIconTag;
        icon.tintColor = [UIColor systemRedColor];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.userInteractionEnabled = NO;
        [self.view addSubview:icon];
    }

    ASDisplayNode *statusNode = TGExtraFindNodeByClassNamePrefix(self, @"ChatMessageDateAndStatusNode");
    if (statusNode.view) {
        CGRect statusFrame = [self.view convertRect:statusNode.view.bounds fromView:statusNode.view];
        icon.frame = CGRectMake(statusFrame.origin.x - 18.0,
                                statusFrame.origin.y + (statusFrame.size.height - 14.0) / 2.0,
                                14.0,
                                14.0);
        icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                UIViewAutoresizingFlexibleRightMargin |
                                UIViewAutoresizingFlexibleTopMargin |
                                UIViewAutoresizingFlexibleBottomMargin;
    } else {
        icon.frame = CGRectMake(MAX(0.0, self.view.bounds.size.width - 38.0),
                                MAX(0.0, self.view.bounds.size.height - 32.0),
                                16.0,
                                16.0);
        icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                UIViewAutoresizingFlexibleTopMargin;
    }

    icon.hidden = NO;
    [self.view bringSubviewToFront:icon];
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
		[TGExtraAntiRevokeUpdater shared];
		[[NSNotificationCenter defaultCenter]
		    addObserverForName:kAutomaticScheduleDidEnqueueNotification
		                object:nil
		                 queue:[NSOperationQueue mainQueue]
		            usingBlock:^(__unused NSNotification *notification) {
		                TGExtraFinishAutomaticScheduleUI();
		            }];
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
