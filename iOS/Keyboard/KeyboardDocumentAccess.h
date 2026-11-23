#import <Foundation/Foundation.h>

// Read only UITextDocumentProxy's public identifier. A disconnecting UIKit
// proxy may throw NSException; nil means wait, never reuse the previous field.
FOUNDATION_EXPORT NSUUID * _Nullable VoiceSeedReadDocumentIdentifier(id _Nullable proxy);
