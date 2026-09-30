#import "Headers.h"

#define kChannelsReadHistory -871347913
#define kUpdateDeleteMessages -1576161051
#define kUpdateDeleteChannelMessages -1020437742
#define kVectorConstructor 481674261
#define kGzipPackedConstructor ((int32_t)0x3072CFA1)

static NSData *TGExtraNeutralizeDeleteUpdates(NSData *data) {
    if (!data || data.length < 8) return nil;

    int32_t constructor = 0;
    memcpy(&constructor, data.bytes, sizeof(constructor));

    if (constructor == kGzipPackedConstructor) {
        const uint8_t *bytes = data.bytes;
        NSUInteger offset = 4;
        NSUInteger packedLength = 0;
        uint8_t first = bytes[offset];

        if (first < 0xFE) {
            packedLength = first;
            offset += 1;
        } else if (first == 0xFE && data.length >= offset + 4) {
            packedLength = (NSUInteger)bytes[offset + 1] |
                           ((NSUInteger)bytes[offset + 2] << 8) |
                           ((NSUInteger)bytes[offset + 3] << 16);
            offset += 4;
        }

        if (packedLength > 0 && offset + packedLength <= data.length) {
            NSData *uncompressed = decompressGzip(bytes + offset, packedLength);
            return TGExtraNeutralizeDeleteUpdates(uncompressed);
        }
        return nil;
    }

    NSMutableData *result = [data mutableCopy];
    uint8_t *bytes = result.mutableBytes;
    NSUInteger length = result.length;
    BOOL changed = NO;

    for (NSUInteger offset = 0; offset + 12 <= length; offset += 4) {
        int32_t word = 0;
        memcpy(&word, bytes + offset, sizeof(word));

        NSUInteger vectorOffset = 0;
        NSUInteger countOffset = 0;
        NSUInteger idsOffset = 0;

        if (word == kUpdateDeleteMessages) {
            vectorOffset = offset + 4;
            countOffset = offset + 8;
            idsOffset = offset + 12;
        } else if (word == kUpdateDeleteChannelMessages) {
            vectorOffset = offset + 12;
            countOffset = offset + 16;
            idsOffset = offset + 20;
        } else {
            continue;
        }

        if (countOffset + 4 > length) continue;
        int32_t vector = 0;
        int32_t count = 0;
        memcpy(&vector, bytes + vectorOffset, sizeof(vector));
        memcpy(&count, bytes + countOffset, sizeof(count));
        if (vector != kVectorConstructor || count <= 0 || count > 65536) continue;

        NSUInteger idsLength = (NSUInteger)count * sizeof(int32_t);
        if (idsOffset + idsLength > length) continue;
        memset(bytes + idsOffset, 0, idsLength);
        changed = YES;
    }

    return changed ? result : nil;
}

%hook MTRequest
%property (nonatomic, strong) NSData *fakeData;
%property (nonatomic, strong) NSNumber *functionID;

- (void)setPayload:(NSData *)payload
          metadata:(id)metadata
     shortMetadata:(id)shortMetadata
    responseParser:(id (^)(NSData *))responseParser {
    int32_t functionID = 0;
    if (payload.length >= sizeof(functionID)) {
        [payload getBytes:&functionID length:sizeof(functionID)];
    }
    self.functionID = @(functionID);

    id (^patchedResponseParser)(NSData *) = ^id(NSData *inputData) {
        NSData *parsed = [TLParser handleResponse:inputData functionID:@(functionID)];
        return responseParser(parsed ?: inputData);
    };

    switch (functionID) {
        case kAccountUpdateOnlineStatus:
            handleOnlineStatus(self, payload);
            break;
        case kMessagesSetTypingAction:
            handleSetTyping(self, payload);
            break;
        case kMessagesReadHistory:
            handleMessageReadReceipt(self, payload);
            break;
        case kStoriesReadStories:
            handleStoriesReadReceipt(self, payload);
            break;
        case kGetSponsoredMessages:
            handleGetSponsoredMessages(self, payload);
            break;
        case kChannelsReadHistory:
            handleChannelsReadReceipt(self, payload);
            break;
        case kSendScreenshotNotification:
            handleSendScreenshotNotification(self, payload);
            break;
        case kMessagesReadMessageContents:
            handleReadMessageContents(self, payload);
            break;
        default:
            break;
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableForwardRestriction]) {
        %orig(payload, metadata, shortMetadata, patchedResponseParser);
    } else {
        %orig(payload, metadata, shortMetadata, responseParser);
    }
}

%end

%hook MTRequestMessageService

- (void)addRequest:(MTRequest *)request {
    if (request.fakeData) {
        @try {
            if (request.completed) {
                NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                MTRequestResponseInfo *info = [[%c(MTRequestResponseInfo) alloc]
                    initWithNetworkType:1 timestamp:now duration:0.045];
                id result = request.responseParser(request.fakeData);
                request.completed(result, info, nil);
            }
        } @catch (NSException *exception) {
            customLog2(@"Exception in MTRequestMessageService hook: %@", exception);
        }
        return;
    }
    %orig;
}

%end

%hook UITextField

- (void)setSecureTextEntry:(BOOL)enabled {
    if (enabled && [[NSUserDefaults standardUserDefaults]
                       boolForKey:kDisableScreenshotNotification]) {
        %orig(NO);
        return;
    }
    %orig;
}

%end

%hook UIView

- (void)_setSecureContents:(BOOL)secure {
    if ([[NSUserDefaults standardUserDefaults]
            boolForKey:kDisableScreenshotNotification]) {
        return;
    }
    %orig;
}

%end

%hook MTProto

- (id)parseMessage:(NSData *)data {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kAntiRevoke]) {
        NSData *patched = TGExtraNeutralizeDeleteUpdates(data);
        if (patched) return %orig(patched);
    }
    return %orig;
}

%end
