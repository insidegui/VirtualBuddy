#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSImage (DesktopPicture)

@property (nonatomic, readonly, class) NSImage *_Nullable desktopPicture;

+ (void)desktopPictureForScreen:(NSScreen *)screen completion:(void(^)(NSImage *_Nullable desktopPicture))completion;

@end

NS_ASSUME_NONNULL_END
