#import "KeyboardDocumentAccess.h"

// Foundation-only protocol permits regression tests with a disconnected proxy
// without launching UIKit. The selector is the public UITextDocumentProxy API.
@protocol VoiceSeedDocumentIdentifying <NSObject>
@property (nonatomic, readonly, nullable) NSUUID *documentIdentifier;
@end

NSUUID *VoiceSeedReadDocumentIdentifier(id proxy) {
    @try {
        id identifier = [(id<VoiceSeedDocumentIdentifying>)proxy documentIdentifier];
        return [identifier isKindOfClass:NSUUID.class] ? identifier : nil;
    } @catch (NSException *exception) {
        return nil;
    }
}
