#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>

// Small macOS fixture for the bridge's lifecycle/ownership checks, not a UIKit
// implementation. Production is compiled separately against the iOS SDK.
@interface UIView : NSObject
@property (nonatomic) CGRect bounds;
@property (nonatomic, strong) UIView *maskView;
@property (nonatomic, strong) CALayer *layer;
@end
@interface UIImage : NSObject
@end
@interface UITapGestureRecognizer : NSObject
- (CGPoint)locationInView:(UIView *)view;
@end
