#import <Foundation/Foundation.h>
#import <zlib.h>
#import "../Sources/tgapi/ManualReadResponse.h"

static NSData *words(const uint32_t *values, NSUInteger count) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i < count; i++) {
        uint32_t v = values[i];
        uint8_t bytes[] = { v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255 };
        [data appendBytes:bytes length:4];
    }
    return data;
}
static NSData *gzipPacked(NSData *data) {
    z_stream stream = {0};
    int initStatus = deflateInit2(&stream, 6, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY);
    NSCAssert(initStatus == Z_OK, @"gzip init");
    NSMutableData *compressed = [NSMutableData dataWithLength:compressBound((uLong)data.length) + 64];
    stream.next_in = (Bytef *)data.bytes;
    stream.avail_in = (uInt)data.length;
    stream.next_out = compressed.mutableBytes;
    stream.avail_out = (uInt)compressed.length;
    int finishStatus = deflate(&stream, Z_FINISH);
    NSCAssert(finishStatus == Z_STREAM_END, @"gzip finish");
    compressed.length = stream.total_out;
    deflateEnd(&stream);
    uint32_t constructor = 0x3072cfa1;
    NSMutableData *result = [words(&constructor, 1) mutableCopy];
    NSUInteger length = compressed.length;
    if (length < 254) {
        uint8_t byte = (uint8_t)length;
        [result appendBytes:&byte length:1];
    } else {
        uint8_t header[] = {254, length & 255, (length >> 8) & 255, (length >> 16) & 255};
        [result appendBytes:header length:4];
    }
    [result appendData:compressed];
    while (result.length % 4 != 0) [result appendBytes:"\0" length:1];
    return result;
}
static BOOL accepted(NSData *data, uint32_t function) {
    return [TGExtraManualReadResponse decodeData:data requestFunction:function].accepted;
}
int main(void) {
    @autoreleasepool {
        const uint32_t read = 0x0e306d3a, channel = 0xcc104937, topic = 0xf731a9f4;
        uint32_t validWords[] = {0x84d19185, 123, 1};
        NSData *valid = words(validWords, 3);
        NSCAssert(accepted(valid, read), @"affectedMessages");
        NSMutableData *padded = [valid mutableCopy];
        [padded appendData:words((uint32_t[]){0, 0}, 2)];
        NSCAssert(accepted(padded, read), @"Valid prefix with aligned trailing data must not become a false error");
        NSCAssert(!accepted(valid, channel), @"Do not accept a response for the wrong method family");
        NSData *yes = words((uint32_t[]){0x997275b5}, 1);
        NSData *no = words((uint32_t[]){0xbc799737}, 1);
        NSCAssert(accepted(yes, channel) && accepted(yes, topic), @"boolTrue");
        NSCAssert(!accepted(no, channel) && !accepted(no, topic), @"Never hide a negative acknowledgement");
        NSCAssert(accepted(gzipPacked(valid), read), @"gzip affectedMessages");
        NSCAssert(accepted(gzipPacked(yes), topic), @"gzip boolTrue");
        NSCAssert(!accepted(gzipPacked(no), topic), @"gzip boolFalse");
        NSCAssert(accepted(gzipPacked(gzipPacked(valid)), read), @"bounded nested gzip");
        NSCAssert(!accepted(gzipPacked(gzipPacked(gzipPacked(gzipPacked(valid)))), read), @"Reject excessive nesting");
        NSMutableData *envelope = [words((uint32_t[]){0xf35c6d01, 0, 0}, 3) mutableCopy];
        [envelope appendData:valid];
        NSCAssert(accepted(envelope, read), @"rpc_result envelope");
        NSCAssert(!accepted(words((uint32_t[]){0x2144ca19, 400}, 2), read), @"RPC error");
        NSCAssert(!accepted(words((uint32_t[]){0x84d19185, 123}, 2), read), @"Truncated response");
        NSCAssert(!accepted(words((uint32_t[]){0xdeadbeef}, 1), read), @"Unknown response stays unverified");
        NSCAssert(!accepted(yes, 0xdeadbeef), @"Not a manual-read function");
        NSCAssert(!accepted([NSData data], read), @"Empty response");
        NSCAssert(!accepted(words((uint32_t[]){0x3072cfa1, 255}, 2), read), @"Invalid TL length");
        NSCAssert(!accepted(words((uint32_t[]){0x3072cfa1, 10}, 2), read), @"Truncated TL gzip bytes");
        NSCAssert(!accepted(gzipPacked([NSMutableData dataWithLength:65540]), read), @"Bounded inflate output");
        NSMutableData *longYes = [yes mutableCopy];
        uint32_t value = 1;
        for (NSUInteger i = 0; i < 1024; i++) {
            value = value * 1664525 + 1013904223;
            [longYes appendData:words(&value, 1)];
        }
        NSData *longPacked = gzipPacked(longYes);
        NSCAssert(((const uint8_t *)longPacked.bytes)[4] == 254, @"Exercise long TL bytes encoding");
        NSCAssert(accepted(longPacked, channel), @"Long TL gzip bytes");
        NSLog(@"Manual read response: padded/plain/compressed acknowledgements and real errors passed");
    }
    return 0;
}
