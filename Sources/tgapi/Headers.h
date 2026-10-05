#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Logger/Logger.h"
#import "Constants.h"

@interface TLParser : NSObject
+ (NSData *)handleResponse:(NSData *)data functionID:(NSNumber *)ios;
+ (NSNumber *)getMessageIdFromNode:(id)node;
+ (BOOL)isDeleted:(NSNumber *)messageId;
+ (void)rememberDeletedMessageIds:(NSArray<NSNumber *> *)messageIds;
+ (NSData *)prepareAutomaticSchedule:(NSData *)data;
+ (NSData *)prepareDefaultSilent:(NSData *)data;
@end

@interface TGExtraDeletedMessageCleaner : NSObject
+ (void)registerNode:(id)node;
+ (void)bindUI:(UIViewController *)ui presenter:(UIViewController *)presenter;
+ (NSString *)statusForUI:(UIViewController *)ui;
+ (void)recordIds:(NSArray<NSNumber *> *)ids channelId:(NSNumber *)channelId transport:(id)transport;
+ (void)clearForUI:(UIViewController *)ui completion:(void (^)(NSInteger removed, NSInteger unresolved, NSString *error))completion;
@end

@interface TGExtraAdFilter : NSObject
+ (BOOL)nodeIsAdvertisement:(id)node;
@end

@interface TGExtraStoryFilter : NSObject
+ (BOOL)isStoryDecorationClass:(NSString *)name;
@end
void TGExtraRefreshStoryVisibility(void);

@interface MTRpcError : NSObject
- (id)initWithErrorCode:(int)code errorDescription:(id)desc;
@end

@interface MTRequestResponseInfo : NSObject
- (id)initWithNetworkType:(int)a  timestamp:(CGFloat)b  duration:(CGFloat)c;
@end

@interface MTRequest : NSObject
@property (nonatomic, strong) NSNumber *functionID;
@property (nonatomic, strong) NSData *fakeData;
@property (nonatomic, strong) NSData *payload;
@property (nonatomic, copy) void (^completed)(id boxedResponse, MTRequestResponseInfo *info, MTRpcError *error);
@property (nonatomic, strong, readonly) id (^responseParser)(NSData *);
@end

// Function Handlers
#ifdef __cplusplus
extern "C" {
#endif
void handleOnlineStatus(MTRequest *request, NSData *payload);
void handleSetTyping(MTRequest *request, NSData *payload);
void handleMessageReadReceipt(MTRequest *request, NSData *payload);
void handleStoriesReadReceipt(MTRequest *request, NSData *payload);
void handleGetSponsoredMessages(MTRequest *request, NSData *payload);
void handleChannelsReadReceipt(MTRequest *request, NSData *payload);
void handleSendScreenshotNotification(MTRequest *request, NSData *payload);
void handleReadMessageContents(MTRequest *request, NSData *payload);
NSData *decompressGzip(const void *input, size_t inputLen);
#ifdef __cplusplus
}
#endif
