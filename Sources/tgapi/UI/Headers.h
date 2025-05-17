#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <roothide.h>
#import "../Constants.h"

@interface TGExtra : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

@interface TGLocalization : NSObject
- (NSString *)get:(NSString *)queryString;
- (id)initWithVersion:(int)a code:(id)b dict:(id)c isActive:(BOOL)d;
@end

@interface TGExtraLocalization  : NSObject
@property (nonatomic, strong ) TGLocalization *localization;
+ (instancetype)shared;
+ (NSString *)localizedStringForKey:(NSString *)key;
@end


@interface LanguageSelector : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

@interface LocationSelector : UIViewController <MKMapViewDelegate>
@end
