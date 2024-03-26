#import "VZGraphicsDisplay+Screenshot.h"

#import <VirtualCore/VirtualizationPrivate.h>

@implementation VZGraphicsDisplay (Screenshot)

- (BOOL)vb_supportsScreenshotSPI
{
    static dispatch_once_t onceToken;
    static BOOL supports;
    dispatch_once(&onceToken, ^{
        supports = [self respondsToSelector:NSSelectorFromString(@"_takeScreenshotWithCompletionHandler:")];
    });
    return supports;
}

- (void)vb_takeScreenshotWithCompletionHandler:(void(^_Nonnull)(NSImage *_Nullable image, NSError *_Nullable error))completion
{
    #define failure( msg ) [NSError errorWithDomain:@"screenshot" code:1 userInfo:@{NSLocalizedDescriptionKey: msg}]

    if (![self vb_supportsScreenshotSPI]) {
        completion(nil, failure(@"VZGraphicsDisplay doesn't have the _takeScreenshotWithCompletionHandler: method"));
        return;
    }

    [self _takeScreenshotWithCompletionHandler:^(id  _Nullable image, id  _Nullable error) {
        if (image) {
            if (![image isKindOfClass:[NSImage class]]) {
                completion(nil, failure(@"Unexpected image type"));
            } else {
                completion(image, nil);
            }
        } else {
            if ([error isKindOfClass:[NSError class]]) {
                completion(nil, error);
            } else {
                completion(nil, failure(@"Unexpected result: no image nor error"));
            }
        }
    }];
}

@end
