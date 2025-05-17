#import <Foundation/Foundation.h>
#import "Logger.h"

// Declaration for LSBundleProxy
@interface LSBundleProxy : NSObject
@property (nonatomic, assign, readonly) NSDictionary *entitlements;
@property (nonatomic, assign, readonly) NSDictionary *groupContainerURLs;
+ (instancetype)bundleProxyForCurrentProcess;
@end

// Static queue for logging
static dispatch_queue_t logQueue;

// Static function to fetch App Group info
static NSDictionary *getAppGroup() {
    static NSDictionary *cachedGroup = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        LSBundleProxy *bundleProxy = [LSBundleProxy bundleProxyForCurrentProcess];
        NSDictionary *entitlements = bundleProxy.entitlements;

        if (entitlements) {
            NSArray *appGroups = entitlements[@"com.apple.security.application-groups"];
            if (appGroups && appGroups.count > 0) {
                NSString *appGroupName = appGroups.firstObject;
                NSURL *appGroupURL = bundleProxy.groupContainerURLs[appGroupName];
                NSString *appGroupPath = appGroupURL.path;

                if (appGroupName && appGroupPath) {
                    cachedGroup = @{
                        @"name": appGroupName,
                        @"path": appGroupPath
                    };
                } else {
                    cachedGroup = nil;
                }
            }
        }
    });

    return cachedGroup;
}

// Static function to get the log file path
static NSString *logFilePath() {
    static NSString *path = nil;
    static dispatch_once_t token;

    dispatch_once(&token, ^{
        NSDictionary *appGroup = getAppGroup();
        NSFileManager *fileManager = [NSFileManager defaultManager];

        if (appGroup) {
            NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
            NSString *chocoWhoreDir = [appGroup[@"path"] stringByAppendingPathComponent:@"group.choco.whore"];
            NSString *logFileName = [NSString stringWithFormat:@"%@.txt", bundleIdentifier];
            path = [chocoWhoreDir stringByAppendingPathComponent:logFileName];

            // Ensure the directory exists
            if (![fileManager fileExistsAtPath:chocoWhoreDir]) {
                NSError *error = nil;
                [fileManager createDirectoryAtPath:chocoWhoreDir
                       withIntermediateDirectories:YES
                                        attributes:nil
                                             error:&error];
                if (error) {
                    NSLog(@"Failed to create directory %@: %@", chocoWhoreDir, error.localizedDescription);
                }
            }

            // Ensure the file exists
            if (![fileManager fileExistsAtPath:path]) {
                [fileManager createFileAtPath:path contents:nil attributes:nil];
            }
        } else {
            // Fallback to the Documents directory
            path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/chocoLogs.txt"];

            // Ensure the file exists
            if (![fileManager fileExistsAtPath:path]) {
                [fileManager createFileAtPath:path contents:nil attributes:nil];
            }
        }
    });

    return path;
}

// Static logging function
void customLog(NSString *format, ...) {
	static dispatch_once_t token;
	dispatch_once(&token, ^{
		logQueue = dispatch_queue_create("com.choco.whore", DISPATCH_QUEUE_SERIAL);
	});
	
	va_list args;
	va_start(args, format);
	
	NSString *formattedMessage = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
		
    dispatch_async(logQueue, ^{
        // Format the log message
        NSDate *currentDate = [NSDate date];
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *dateString = [dateFormatter stringFromDate:currentDate];

        NSString *logMessage = [NSString stringWithFormat:@"%@ - %@\n", dateString, formattedMessage];

        // Write the log message to the file
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath()];
        if (fileHandle) {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
        }
    });
}

void customLog2(NSString *format, ...) {
	va_list args;
	va_start(args, format);
	
	NSString *formattedMessage = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
		
    // Format the log message
        NSDate *currentDate = [NSDate date];
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *dateString = [dateFormatter stringFromDate:currentDate];

        NSString *logMessage = [NSString stringWithFormat:@"%@ - %@\n", dateString, formattedMessage];

        // Write the log message to the file
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath()];
        if (fileHandle) {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
        }
}
