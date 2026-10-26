#import "Headers.h"
#import <objc/runtime.h>

@interface LocationSelector ()
@property (nonatomic, strong) MKMapView *mapView;
@end

@implementation LocationSelector

- (void)viewDidLoad {
    [super viewDidLoad];
	
	[self setupMapView];
	[self setupCloseButton];
	[self setupMapSelectorSegment];
	[self loadDefaultLocation];
}

- (void)setupMapView {
	self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.delegate = self;
    [self.view addSubview:self.mapView];
	
	UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)];
    [self.mapView addGestureRecognizer:tapGesture];
}

- (void)setupCloseButton {
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setImage:[UIImage systemImageNamed:@"xmark.square.fill"] forState:UIControlStateNormal];
    closeButton.tintColor = [UIColor redColor];
    [closeButton addTarget:self action:@selector(closeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *closeBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:closeButton];
    self.navigationItem.leftBarButtonItem = closeBarButtonItem;
}

- (void)closeButtonTapped {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil]; 
	
}

- (void)setupMapSelectorSegment {
    NSArray *mapTypes = @[[TGExtraLocalization localizedStringForKey:@"MAP_STANDARD"],
                         [TGExtraLocalization localizedStringForKey:@"MAP_SATELLITE"],
                         [TGExtraLocalization localizedStringForKey:@"MAP_HYBRID"]];
    UISegmentedControl *segmentControl = [[UISegmentedControl alloc] initWithItems:mapTypes];
    segmentControl.selectedSegmentIndex = 0;

    [segmentControl addTarget:self action:@selector(mapTypeChanged:) forControlEvents:UIControlEventValueChanged];

    segmentControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:segmentControl];

    [NSLayoutConstraint activateConstraints:@[
        [segmentControl.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [segmentControl.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [segmentControl.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [segmentControl.heightAnchor constraintEqualToConstant:32]
    ]];
}

- (void)mapTypeChanged:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 0:
            self.mapView.mapType = MKMapTypeStandard;
            break;
        case 1:
            self.mapView.mapType = MKMapTypeSatellite;
            break;
        case 2:
            self.mapView.mapType = MKMapTypeHybrid;
            break;
        default:
            break;
    }
}

- (void)loadDefaultLocation {
	CGFloat savedLongitude = [[NSUserDefaults standardUserDefaults] floatForKey:FAKE_LONGITUDE_KEY];
    CGFloat savedLatitude = [[NSUserDefaults standardUserDefaults] floatForKey:FAKE_LATITUDE_KEY];
    
    CLLocationCoordinate2D centerCoordinate;
    if (savedLongitude && savedLatitude) {
        centerCoordinate = CLLocationCoordinate2DMake(savedLatitude, savedLongitude);
        // Add a pin for the saved location
        [self addPinAtCoordinate:centerCoordinate withTitle:[TGExtraLocalization localizedStringForKey:@"LOCATION_LAST_SELECTED"]];
    } else {
        centerCoordinate = CLLocationCoordinate2DMake(37.7749, -122.4194); // Default to San Francisco
    }
    
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(centerCoordinate, 5000, 5000);
    [self.mapView setRegion:region animated:YES]; 
}

- (void)handleMapTap:(UITapGestureRecognizer *)gesture {
    // Get the tap location
    CGPoint touchPoint = [gesture locationInView:self.mapView];
    
    // Convert to map coordinates
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:touchPoint toCoordinateFromView:self.mapView];
    
    // Add a pin at the selected location
    [self addPinAtCoordinate:coordinate withTitle:[TGExtraLocalization localizedStringForKey:@"LOCATION_SELECTED"]];
    
    // Save the selected location to UserDefaults
    [[NSUserDefaults standardUserDefaults] setFloat:coordinate.longitude forKey:FAKE_LONGITUDE_KEY];
    [[NSUserDefaults standardUserDefaults] setFloat:coordinate.latitude forKey:FAKE_LATITUDE_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"TGExtraLocationChanged" object:nil];
}

- (void)addPinAtCoordinate:(CLLocationCoordinate2D)coordinate withTitle:(NSString *)title {
    MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
    annotation.coordinate = coordinate;
    annotation.title = title;
    
    [self.mapView removeAnnotations:self.mapView.annotations];
    [self.mapView addAnnotation:annotation];
}

@end
