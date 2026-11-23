#import "../Keyboard/KeyboardDocumentAccess.h"

@interface SyntheticDocument : NSObject
@property (nonatomic, strong) NSUUID *identifier;
@property (nonatomic) BOOL disconnected;
@end

@implementation SyntheticDocument
- (NSUUID *)documentIdentifier {
    if (self.disconnected) {
        // Same exception class as the iPhone's stale UIKit document interface.
        [NSException raise:NSInvalidArgumentException format:@"synthetic disconnected document"];
    }
    return self.identifier;
}
@end

int main(void) {
    @autoreleasepool {
        SyntheticDocument *proxy = [SyntheticDocument new];
        proxy.identifier = [NSUUID UUID];
        NSCAssert([VoiceSeedReadDocumentIdentifier(proxy) isEqual:proxy.identifier], @"Connected field must retain its identity");
        for (int i = 0; i < 50; i++) {
            NSUUID *previous = proxy.identifier;
            proxy.disconnected = YES;
            NSCAssert(VoiceSeedReadDocumentIdentifier(proxy) == nil, @"Disconnect must not crash or return a stale field");
            proxy.identifier = [NSUUID UUID];
            proxy.disconnected = NO;
            NSUUID *restored = VoiceSeedReadDocumentIdentifier(proxy);
            NSCAssert([restored isEqual:proxy.identifier] && ![restored isEqual:previous], @"Reconnect must use the new field");
        }
        NSCAssert(VoiceSeedReadDocumentIdentifier(nil) == nil, @"Missing proxy is not an input field");
        NSCAssert(VoiceSeedReadDocumentIdentifier([NSObject new]) == nil, @"Unconnected proxy must not crash");
        puts("PASS: keyboard document access survives 50 disconnect/reconnect cycles; synthetic proxies only");
    }
    return 0;
}
