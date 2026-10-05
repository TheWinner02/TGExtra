#import "Headers.h"

@implementation TGExtraLocalization

+ (instancetype)shared {
	static TGExtraLocalization *instance;
	static dispatch_once_t token;
	dispatch_once(&token, ^{
		instance = [TGExtraLocalization new];
		[instance loadDefault];
	});
	return instance;
}

- (void)loadDefault {
	NSString *selectedLanguageCode = [[NSUserDefaults standardUserDefaults] stringForKey:@"TGExtraLanguage"];

	if (!selectedLanguageCode) {
		selectedLanguageCode = @"en";
	}

	NSString *localizationFilePath = [NSString stringWithFormat:@"%@/TGExtra.bundle/%@.lproj/Localizable.strings", jbroot(@"/Library/Application Support/TGExtra"), selectedLanguageCode];
	if (![[NSFileManager defaultManager] fileExistsAtPath:localizationFilePath]) {
		localizationFilePath = [NSString stringWithFormat:@"%@/TGExtra.bundle/%@.lproj/Localizable.strings", [[NSBundle mainBundle] resourcePath], selectedLanguageCode];
	}

	NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:localizationFilePath];

	self.localization = [[objc_getClass("TGLocalization") alloc] initWithVersion:96929692
                                                                   code:selectedLanguageCode
                                                                   dict:dict
                                                              isActive:YES];

}

+ (NSString *)localizedStringForKey:(NSString *)key {
	if (!key) return nil;

	NSString *localizedString = [[TGExtraLocalization shared].localization get:key];

	if (!localizedString || [localizedString isEqualToString:key]) {
		NSString *englishPath = [NSString stringWithFormat:@"%@/TGExtra.bundle/en.lproj/Localizable.strings", jbroot(@"/Library/Application Support/TGExtra")];
		if (![[NSFileManager defaultManager] fileExistsAtPath:englishPath]) {
			englishPath = [NSString stringWithFormat:@"%@/TGExtra.bundle/en.lproj/Localizable.strings", [[NSBundle mainBundle] resourcePath]];
		}
		NSDictionary *english = [NSDictionary dictionaryWithContentsOfFile:englishPath];
		return english[key] ?: key;
	}

	return localizedString;
}
@end
