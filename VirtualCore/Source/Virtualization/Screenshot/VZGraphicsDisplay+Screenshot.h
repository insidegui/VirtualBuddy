#import <Virtualization/Virtualization.h>

NS_ASSUME_NONNULL_BEGIN

@interface VZGraphicsDisplay (Screenshot)

/// Wraps Virtualization SPI to make it safer to call from Swift.
/// Checks for SPI availability and that the completion block types match the ones we expect.
- (void)vb_takeScreenshotWithCompletionHandler:(void(^_Nonnull)(NSImage *_Nullable image, NSError *_Nullable error))completion NS_SWIFT_UI_ACTOR API_AVAILABLE(macos(14.0));

@end

NS_ASSUME_NONNULL_END
