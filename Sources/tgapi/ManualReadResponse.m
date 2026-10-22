#import "ManualReadResponse.h"
#import <zlib.h>

static const NSUInteger TGExtraReadResponseLimit = 65536;

static uint32_t TGExtraReadWord(NSData *data, NSUInteger offset) {
    const uint8_t *p = (const uint8_t *)data.bytes + offset;
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

@interface TGExtraManualReadResponse ()
@property (nonatomic, readwrite) BOOL accepted;
@property (nonatomic, copy, readwrite) NSString *diagnostic;
@end

@implementation TGExtraManualReadResponse
+ (instancetype)result:(BOOL)accepted diagnostic:(NSString *)diagnostic {
    TGExtraManualReadResponse *result = [self new];
    result.accepted = accepted;
    result.diagnostic = diagnostic;
    return result;
}

+ (instancetype)decodeData:(NSData *)data requestFunction:(uint32_t)function {
    if (function != 0x0e306d3a && function != 0xcc104937 && function != 0xf731a9f4) {
        return [self result:NO diagnostic:@"unsupported read request"];
    }
    return [self decode:data function:function depth:0];
}

+ (instancetype)decode:(NSData *)data function:(uint32_t)function depth:(NSUInteger)depth {
    if (depth > 3 || data.length < 4 || data.length > TGExtraReadResponseLimit || data.length % 4 != 0) {
        return [self result:NO diagnostic:[NSString stringWithFormat:@"invalid response size %lu/depth %lu", (unsigned long)data.length, (unsigned long)depth]];
    }
    uint32_t constructor = TGExtraReadWord(data, 0);
    NSString *shape = [NSString stringWithFormat:@"constructor %08x, bytes %lu", constructor, (unsigned long)data.length];
    if (constructor == 0x997275b5) return [self result:YES diagnostic:shape];
    if (constructor == 0xbc799737) return [self result:NO diagnostic:[shape stringByAppendingString:@", boolFalse"]];
    if (constructor == 0x84d19185) {
        // Match a native TL parser: require the full known object, not an exact
        // buffer size. Some transports include aligned trailing data/padding.
        BOOL valid = function == 0x0e306d3a && data.length >= 12 &&
            TGExtraReadWord(data, 4) <= INT32_MAX && TGExtraReadWord(data, 8) <= INT32_MAX;
        return [self result:valid diagnostic:[shape stringByAppendingString:valid ? @", affectedMessages" : @", invalid affectedMessages"]];
    }
    if (constructor == 0xf35c6d01 && data.length >= 16) { // rpc_result
        TGExtraManualReadResponse *inner = [self decode:[data subdataWithRange:NSMakeRange(12, data.length - 12)] function:function depth:depth + 1];
        return [self result:inner.accepted diagnostic:[@"rpc_result > " stringByAppendingString:inner.diagnostic]];
    }
    if (constructor == 0x3072cfa1 && data.length >= 8) { // gzip_packed bytes
        const uint8_t *bytes = (const uint8_t *)data.bytes;
        NSUInteger length = bytes[4];
        NSUInteger offset = 5;
        if (length == 254) {
            length = (NSUInteger)bytes[5] | ((NSUInteger)bytes[6] << 8) | ((NSUInteger)bytes[7] << 16);
            offset = 8;
        } else if (length == 255) {
            return [self result:NO diagnostic:@"invalid gzip TL length"];
        }
        if (length == 0 || length > data.length - offset) return [self result:NO diagnostic:@"truncated gzip TL bytes"];
        z_stream stream = {0};
        stream.next_in = (Bytef *)bytes + offset;
        stream.avail_in = (uInt)length;
        NSMutableData *output = [NSMutableData dataWithLength:TGExtraReadResponseLimit];
        stream.next_out = (Bytef *)output.mutableBytes;
        stream.avail_out = (uInt)output.length;
        if (inflateInit2(&stream, 15 + 32) != Z_OK) return [self result:NO diagnostic:@"gzip init failed"];
        int status = inflate(&stream, Z_FINISH);
        NSUInteger outputLength = stream.total_out;
        BOOL complete = status == Z_STREAM_END && stream.avail_in == 0;
        inflateEnd(&stream);
        if (!complete || outputLength == 0) return [self result:NO diagnostic:@"invalid/oversized gzip response"];
        output.length = outputLength;
        TGExtraManualReadResponse *inner = [self decode:output function:function depth:depth + 1];
        return [self result:inner.accepted diagnostic:[@"gzip > " stringByAppendingString:inner.diagnostic]];
    }
    if (constructor == 0x2144ca19 && data.length >= 8) {
        return [self result:NO diagnostic:[NSString stringWithFormat:@"rpc_error code %d", (int32_t)TGExtraReadWord(data, 4)]];
    }
    return [self result:NO diagnostic:[shape stringByAppendingString:@", unrecognized"]];
}
@end
