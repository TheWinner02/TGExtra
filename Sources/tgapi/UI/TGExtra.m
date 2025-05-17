#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Icons.h"
#import "Headers.h"

#define TGLoc(key) [TGExtraLocalization localizedStringForKey:(key)]

@interface TGExtra ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSString *cacheSize;
@end

@implementation TGExtra

- (void)viewDidLoad {

	[self setupTableView];
	[self setupIconAsHeader];
	[self setupApplyButton];
	self.title = @"TGExtra";

	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeLanguage)
                                                 name:@"LanguageChangedNotification"
                                               object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeFakeLocation)
                                                 name:@"TGExtraLocationChanged"
                                               object:nil];
}

- (void)didChangeLanguage {
	[self.tableView reloadData];
}

- (void)didChangeFakeLocation {
	NSIndexSet *section = [NSIndexSet indexSetWithIndex:4];
	[self.tableView reloadSections:section withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)setupTableView {
	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.delegate = self;
	self.tableView.dataSource = self;
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;

	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
    	[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
	]];
}

- (void)setupIconAsHeader {
    UIView *logoContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, 100)];

    // Logo Image
	//NSString *imagePath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Choco.png"];
	NSData *imageData = [[NSData alloc] initWithBase64EncodedString:CHOCOPNG options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage imageWithData:imageData]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.layer.cornerRadius = 100 / 4;
	iconView.userInteractionEnabled = YES;
    iconView.clipsToBounds = YES;
    iconView.contentMode = UIViewContentModeScaleAspectFill;

    [logoContainer addSubview:iconView];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerYAnchor constraintEqualToAnchor:logoContainer.centerYAnchor],
        [iconView.centerXAnchor constraintEqualToAnchor:logoContainer.centerXAnchor],
        [iconView.widthAnchor constraintEqualToConstant:100],
        [iconView.heightAnchor constraintEqualToConstant:100]
    ]];

    self.tableView.tableHeaderView = logoContainer;
}

- (void)setupApplyButton {
	UIButton *applyChangesButton = [UIButton buttonWithType:UIButtonTypeSystem];
	UIImage *applyImage = [UIImage systemImageNamed:@"checkmark.square"];
	applyImage = [applyImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	applyChangesButton.tintColor = [UIColor systemPinkColor];
	[applyChangesButton setImage:applyImage forState:UIControlStateNormal];
	[applyChangesButton addTarget:self action:@selector(applyChanges) forControlEvents:UIControlEventTouchUpInside];
	UIBarButtonItem *applyButtonItem = [[UIBarButtonItem alloc] initWithCustomView:applyChangesButton];
	self.navigationItem.rightBarButtonItems = @[applyButtonItem];
}

- (void)applyChanges {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:TGLoc(@"APPLY")
                                                                   message:TGLoc(@"APPLY_CHANGES")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:TGLoc(@"OK")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
		[[UIApplication sharedApplication] performSelector:@selector(suspend)];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			exit(0);
		});
	}];

    [alert addAction:okAction];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:TGLoc(@"CANCEL")
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIColor *)dynamicColorBW {
    static dispatch_once_t token;
    static UIColor *cached;
    dispatch_once(&token, ^{
        cached = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
            if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor whiteColor];
            } else {
                return [UIColor blackColor];
            }
        }];
    });
    return cached;
}

# pragma mark - UITableViewDataSource

typedef NS_ENUM(NSInteger, TABLE_VIEW_SECTIONS) {
    GHOST_MODE = 0,
    READ_RECEIPT = 1,
    MISC = 2,
    FILE_FIXER = 3,
    FAKE_LOCATION = 4,
    LANGUAGE = 5,
	CREDITS = 6,
};

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 7;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case GHOST_MODE:
		   return 17;
		case READ_RECEIPT:
		   return 2;
		case MISC:
		   return 2;
		case FILE_FIXER:
		   return 2;
		case FAKE_LOCATION:
		   return 2;
		case LANGUAGE:
		   return 1;
		case CREDITS:
		   return 2;
		default:
		   return 0;
	}
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {

	switch (section) {
		case GHOST_MODE:
		   return TGLoc(@"GHOST_MODE_SECTION_HEADER");
		case READ_RECEIPT:
		   return TGLoc(@"READ_RECEIPT_SECTION_HEADER");
		case MISC:
		   return TGLoc(@"MISC_SECTION_HEADER");
		case FILE_FIXER:
		   return TGLoc(@"FILE_FIXER_SECTION_HEADER");
		case FAKE_LOCATION:
		   return TGLoc(@"FAKE_LOCATION_SECTION_HEADER");
		case LANGUAGE:
		   return TGLoc(@"LANGUAGE_SECTION_HEADER");
		case CREDITS:
		   return TGLoc(@"CREDITS_SECTION_HEADER");
		default:
		   return nil;
	}
	return nil;
}

- (UITableViewCell *)switchCellFromTableView:(UITableView *)tableView {
	UITableViewCell *switchCell = [tableView dequeueReusableCellWithIdentifier:@"switchCell"];
	if (!switchCell) {
		switchCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"switchCell"];
	}

	return switchCell;
}

- (UITableViewCell *)normalCellFromTableView:(UITableView *)tableView {
	UITableViewCell *normalCell = [tableView dequeueReusableCellWithIdentifier:@"normalCell"];
	if (!normalCell) {
		normalCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"normalCell"];
	}

	return normalCell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell;

	if (indexPath.section == 0) { // GHOST MOODE
		cell = [self switchCellFromTableView:tableView];
		cell.imageView.image = nil;

		if (indexPath.row == 0) {
			cell.textLabel.text = TGLoc(@"DISABLE_ONLINE_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_ONLINE_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 1) {
			cell.textLabel.text = TGLoc(@"DISABLE_TYPING_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_TYPING_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 2) {
			cell.textLabel.text = TGLoc(@"DISABLE_RECORDING_VIDEO_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 3) {
			cell.textLabel.text = TGLoc(@"DISABLE_UPLOADING_VIDEO_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 4) {
			cell.textLabel.text = TGLoc(@"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 5) {
			cell.textLabel.text = TGLoc(@"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 6) {
			cell.textLabel.text = TGLoc(@"DISABLE_UPLOADING_PHOTO_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 7) {
			cell.textLabel.text = TGLoc(@"DISABLE_UPLOADING_FILE_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 8) {
			cell.textLabel.text = TGLoc(@"DISABLE_CHOOSING_LOCATION_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 9) {
			cell.textLabel.text = TGLoc(@"DISABLE_CHOOSING_CONTACT_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_CHOOSING_CONTACT_SUBTITLE");
		}
		else if (indexPath.row == 10) {
			cell.textLabel.text = TGLoc(@"DISABLE_PLAYING_GAME_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_PLAYING_GAME_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 11) {
			cell.textLabel.text = TGLoc(@"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 12) {
			cell.textLabel.text = TGLoc(@"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE");
		}
		else if (indexPath.row == 13) {
			cell.textLabel.text = TGLoc(@"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 14) {
			cell.textLabel.text = TGLoc(@"DISABLE_CHOOSING_STICKER_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 15) {
			cell.textLabel.text = TGLoc(@"DISABLE_EMOJI_INTERACTION_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE");
		}
		else if (indexPath.row == 16) {
			cell.textLabel.text = TGLoc(@"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE");
		}

		UISwitch *toggle = (UISwitch *)cell.accessoryView;
		if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
			toggle = [[UISwitch alloc] init];
		}

		NSString *switchKey = [self switchKeyForIndexPath:indexPath];
		toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
		[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
		toggle.tag = 1000 + (indexPath.section *1000) + indexPath.row;
		cell.accessoryView = toggle;

		cell.textLabel.numberOfLines = 0;
		cell.detailTextLabel.numberOfLines = 0;
		return cell;

	}
	else if (indexPath.section == 1) { // Read Receipts
		cell = [self switchCellFromTableView:tableView];
		cell.imageView.image = nil;

		if (indexPath.row == 0) {
			cell.textLabel.text = TGLoc(@"DISABLE_MESSAGE_READ_RECEIPT_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE");
		}
		else if (indexPath.row == 1) {
			cell.textLabel.text = TGLoc(@"DISABLE_STORY_READ_RECEIPT_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_STORY_READ_RECEIPT_SUBTITLE");
		}

		UISwitch *toggle = (UISwitch *)cell.accessoryView;
		if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
			toggle = [[UISwitch alloc] init];
		}

		NSString *switchKey = [self switchKeyForIndexPath:indexPath];
		toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
		[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
		toggle.tag = 1000 + (indexPath.section *1000) + indexPath.row;
		cell.accessoryView = toggle;

		cell.textLabel.numberOfLines = 0;
		cell.detailTextLabel.numberOfLines = 0;
		return cell;
	}
	else if (indexPath.section == 2) { // MISC
		cell = [self switchCellFromTableView:tableView];
		cell.imageView.image = nil;

		if (indexPath.row == 0) {
			cell.textLabel.text = TGLoc(@"DISABLE_ALL_ADS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_ALL_ADS_SUBTITLE");
		}
		else if (indexPath.row == 1) {
			cell.textLabel.text = TGLoc(@"ENABLE_SAVING_PROTECTED_CONTENT_TITLE");
			cell.detailTextLabel.text = TGLoc(@"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE");
		}

		UISwitch *toggle = (UISwitch *)cell.accessoryView;
		if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
			toggle = [[UISwitch alloc] init];
		}

		NSString *switchKey = [self switchKeyForIndexPath:indexPath];
		toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
		[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
		toggle.tag = 1000 + (indexPath.section *1000) + indexPath.row;
		cell.accessoryView = toggle;

		cell.textLabel.numberOfLines = 0;
		cell.detailTextLabel.numberOfLines = 0;
		return cell;

	}
	if (indexPath.section == 3) { // File Picker Fix
		if (indexPath.row ==0) { //Enable File Picker Fix
			cell = [self switchCellFromTableView:tableView];

			cell.imageView.image = [UIImage systemImageNamed:@"folder.fill.badge.gear"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"FIX_FILE_PICKER_TITLE");
			cell.detailTextLabel.text = TGLoc(@"FIX_FILE_PICKER_SUBTITLE");

			UISwitch *toggle = (UISwitch *)cell.accessoryView;
			if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
				toggle = [[UISwitch alloc] init];
			}

			NSString *switchKey = [self switchKeyForIndexPath:indexPath];
			toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
			[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
			toggle.tag = 1000 + (indexPath.section *1000) + indexPath.row;
			cell.accessoryView = toggle;

			cell.textLabel.numberOfLines = 0;
			cell.detailTextLabel.numberOfLines = 0;
			return cell;
		}

		if (indexPath.row == 1) {
			cell = [self normalCellFromTableView:tableView];
			cell.imageView.image = nil;

		    cell.textLabel.text = TGLoc(@"CLEAR_FILE_PICKER_CACHE_TITLE");
		    cell.detailTextLabel.text = TGLoc(@"CLEAR_FILE_PICKER_CACHE_SUBTITLE");
		    cell.imageView.image = [UIImage systemImageNamed:@"trash"];
		    cell.imageView.tintColor = [UIColor redColor];

		    // Initially show a UIActivityIndicator
		    UIActivityIndicatorView *loadingIcon = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
		    [loadingIcon startAnimating];
		    cell.accessoryView = loadingIcon;

		    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
				if (!self.cacheSize) {
					self.cacheSize = [self sizeOfUglyFileFixDirectory];
				}

		        dispatch_async(dispatch_get_main_queue(), ^{
					UITableViewCell *currentCell = [tableView cellForRowAtIndexPath:indexPath];
					if (currentCell == cell) {
						UILabel *sizeLabel = [[UILabel alloc] init];
						sizeLabel.text = self.cacheSize;
						cell.accessoryView = sizeLabel;

						[sizeLabel sizeToFit];
					}
		        });
		    });

			cell.textLabel.numberOfLines = 0;
			cell.detailTextLabel.numberOfLines = 0;
			return cell;
		}
	}

	if (indexPath.section == 4) { // Fake Location
		if (indexPath.row ==0) {
			cell = [self switchCellFromTableView:tableView];

			cell.imageView.image = [UIImage systemImageNamed:@"location.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"ENABLE_FAKE_LOCATION_TITLE");
			cell.detailTextLabel.text = TGLoc(@"ENABLE_FAKE_LOCATION_SUBTITLE");

			UISwitch *toggle = (UISwitch *)cell.accessoryView;
			if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
				toggle = [[UISwitch alloc] init];
			}

			NSString *switchKey = [self switchKeyForIndexPath:indexPath];
			toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
			[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
			toggle.tag = 1000 + (indexPath.section *1000) + indexPath.row;
			cell.accessoryView = toggle;
		}

		if (indexPath.row == 1) {
			cell = [self normalCellFromTableView:tableView];

			cell.imageView.image = [UIImage systemImageNamed:@"location.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"SELECT_FAKE_LOCATION_TITLE");

			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			CGFloat savedLongitude = [defaults floatForKey:FAKE_LONGITUDE_KEY];
			CGFloat savedLatitude = [defaults floatForKey:FAKE_LATITUDE_KEY];

			NSString *savedCord = savedCord = [NSString stringWithFormat:@"lon :%f\nlat :%f", savedLongitude ? : 0, savedLatitude ? : 0];

			cell.textLabel.numberOfLines = 0;
			cell.detailTextLabel.text = savedCord;
		}
		cell.detailTextLabel.numberOfLines = 0;
		return cell;
	}

	if (indexPath.section == 5) { // Language
		cell = [self normalCellFromTableView:tableView];
		if (indexPath.row == 0) {
			cell.textLabel.text = @"Change Language";
			cell.detailTextLabel.text = @"";
			cell.imageView.image = [UIImage systemImageNamed:@"globe"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.imageView.layer.cornerRadius = 40/8;
			cell.imageView.layer.masksToBounds = YES;
			cell.accessoryView = nil;

			cell.textLabel.numberOfLines = 0;
			cell.detailTextLabel.numberOfLines = 0;
			return cell;
		}
	}

	if (indexPath.section == 6) { // Credits
		cell = [self normalCellFromTableView:tableView];

		if (indexPath.row == 0) {
			cell.textLabel.text = @"Chocolate Fluffy (Dumb Whore)";
			cell.detailTextLabel.text = @"Developer";
			cell.detailTextLabel.textColor = [UIColor lightGrayColor];
			NSData *imageData = [[NSData alloc] initWithBase64EncodedString:CHOCOPNG options:NSDataBase64DecodingIgnoreUnknownCharacters];
			cell.imageView.image = [UIImage imageWithData:imageData scale:2.0];
			cell.imageView.layer.cornerRadius = 40/8;
			cell.imageView.layer.masksToBounds = YES;
			cell.accessoryView = nil;

		}
		else if (indexPath.row == 1) {
			cell.textLabel.text = TGLoc(@"DISCLAIMER");
			cell.detailTextLabel.text = @"A note from whore";
			cell.imageView.image = [UIImage systemImageNamed:@"note.text"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.accessoryView = nil;
			cell.detailTextLabel.textColor = [UIColor lightGrayColor];
		}
		cell.textLabel.numberOfLines = 0;
		cell.detailTextLabel.numberOfLines = 0;
		return cell;
	}

    return cell;
}

# pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == FILE_FIXER) { // File Picker Fix
		if (indexPath.row == 1) {
			[self clearFilePickerFixCache];
		}
	}

	if (indexPath.section == FAKE_LOCATION) { // Fake Location
		if (indexPath.row == 1) {
			[self showLocationSelector];
		}
	}

	if (indexPath.section == LANGUAGE) { // Language
		if (indexPath.row == 0) {
			[self showLanguageSelector];
		}
	}

    if (indexPath.section == CREDITS) {
		if (indexPath.row == 0) {
			NSString *base64String = @"aHR0cHM6Ly90Lm1lL3VsdGltYXRlUG9pc29u";
	        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
	        NSString *decodedURL = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];

	        NSURL *url = [NSURL URLWithString:decodedURL];
	        if ([[UIApplication sharedApplication] canOpenURL:url]) {
	            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	        }
		}
		else if (indexPath.row == 1) {
		    [self showDisclaimer];
		}
    }
}

- (void)switchChanged:(UISwitch *)sender {
    NSInteger adjustedTag = sender.tag - 1000;
    NSInteger section = adjustedTag / 1000;
    NSInteger row = adjustedTag % 1000;

    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
    NSString *switchKey = [self switchKeyForIndexPath:indexPath];

    if (switchKey) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:switchKey];
    }
}

- (NSString *)switchKeyForIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            switch (indexPath.row) {
                case 0: return kDisableOnlineStatus;
                case 1: return kDisableTypingStatus;
                case 2: return kDisableRecordingVideoStatus;
                case 3: return kDisableUploadingVideoStatus;
                case 4: return kDisableRecordingVoiceStatus;
                case 5: return kDisableUploadingVoiceStatus;
                case 6: return kDisableUploadingPhotoStatus;
                case 7: return kDisableUploadingFileStatus;
                case 8: return kDisableChoosingLocationStatus;
                case 9: return kDisableChoosingContactStatus;
                case 10: return kDisablePlayingGameStatus;
                case 11: return kDisableRecordingRoundVideoStatus;
                case 12: return kDisableUploadingRoundVideoStatus;
                case 13: return kDisableSpeakingInGroupCallStatus;
                case 14: return kDisableChoosingStickerStatus;
                case 15: return kDisableEmojiInteractionStatus;
                case 16: return kDisableEmojiAcknowledgementStatus;
                default: return nil;
            }
        case 1:
            switch (indexPath.row) {
                case 0: return kDisableMessageReadReceipt;
                case 1: return kDisableStoriesReadReceipt;
                default: return nil;
            }
        case 2:
            switch (indexPath.row) {
                case 0: return kDisableAllAds;
                case 1: return kDisableForwardRestriction;
                default: return nil;
            }
        case 3:
            switch (indexPath.row) {
                case 0: return FILE_PICKER_FIX_KEY;
                default: return nil;
            }
        case 4:
            switch (indexPath.row) {
                case 0: return FAKE_LOCATION_ENABLED_KEY;
                default: return nil;
            }
        default:
            return nil;
    }
}

- (NSString *)sizeOfUglyFileFixDirectory {
	NSString *uglyFixDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:FILE_PICKER_PATH];

    // Calculate size of it recursively
    unsigned long long totalSize = 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *contents = [fileManager subpathsAtPath:uglyFixDirectory];

    for (NSString *path in contents) {
        NSString *fullPath = [uglyFixDirectory stringByAppendingPathComponent:path];
        BOOL isDirectory;
        if ([fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory]) {
            if (!isDirectory) {
                NSDictionary *attributes = [fileManager attributesOfItemAtPath:fullPath error:nil];
                totalSize += [attributes fileSize];
            }
        }
    }

    // Format the size into MB or GB
    NSString *formattedSize;
    if (totalSize >= 1024 * 1024 * 1024) { // if the size is >= 1GB
        formattedSize = [NSString stringWithFormat:@"%.2f GB", totalSize / (1024.0 * 1024.0 * 1024.0)];
    } else {
        formattedSize = [NSString stringWithFormat:@"%.2f MB", totalSize / (1024.0 * 1024.0)];
    }
	return formattedSize;
}

- (void)showDisclaimer {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:TGLoc(@"DISCLAIMER")
		              message:TGLoc(@"AUTHOR_MESSAGE")
		       preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:TGLoc(@"OK")
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];

    [alert addAction:okAction];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showLanguageSelector {
	LanguageSelector *ui = [LanguageSelector new];
	UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:ui];
	[self presentViewController:navVC animated:YES completion:nil];
}

- (void)showLocationSelector {
	LocationSelector *ui = [LocationSelector new];
	UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:ui];
	[self presentViewController:navVC animated:YES completion:nil];
}

- (void)clearFilePickerFixCache {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:TGLoc(@"CACHE_CLEAR_WARNING_TITLE")
                                                                   message:TGLoc(@"CACHE_CLEAR_WARNING_MESSAGE")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:TGLoc(@"OK")
                                                       style:UIAlertActionStyleDestructive
                                                     handler:^(UIAlertAction *action) {
        NSString *uglyFixDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"TGExtraFileFixUsingSomeUglyHacks"];

        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:uglyFixDirectory error:&error];

        if (error) {
            NSLog(@"Failed to remove cache directory: %@", error.localizedDescription);
        } else {
            NSLog(@"Successfully cleared cache: %@", uglyFixDirectory);
        }

		self.cacheSize = @"Cleared";

        // Reload section or row as needed
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexSet *section = [NSIndexSet indexSetWithIndex:FILE_FIXER];
            [self.tableView reloadSections:section withRowAnimation:UITableViewRowAnimationAutomatic];
        });
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:TGLoc(@"CANCEL")
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [alert addAction:cancelAction];
    [alert addAction:okAction];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"LanguageChangedNotification" object:nil];

	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"TGExtralocationChanged" object:nil];

}

@end
