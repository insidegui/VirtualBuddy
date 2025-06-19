#import "NSImage+DesktopPicture.h"

@interface NSScreen (DisplayInfo)

@property (readonly) NSNumber *displayID;

@end

@implementation NSImage (DesktopPicture)

+ (dispatch_queue_t)_vb_desktopPictureQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t _queue;
    dispatch_once(&onceToken, ^{
        _queue = dispatch_queue_create("DesktopPicture", dispatch_queue_attr_make_with_qos_class(NULL, QOS_CLASS_USER_INITIATED, 0));
    });
    return _queue;
}

+ (NSImage *)desktopPicture
{
    return [self _vb_desktopPictureForScreen:[NSScreen mainScreen]];
}

+ (void)desktopPictureForScreen:(NSScreen *)screen completion:(void(^)(NSImage *_Nullable desktopPicture))completion
{
    dispatch_async([self _vb_desktopPictureQueue], ^{
        NSImage *picture = [self _vb_desktopPictureForScreen:screen];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(picture);
        });
    });
}

+ (NSImage *)_vb_desktopPictureForScreen:(NSScreen *)screen
{
    if (!screen) return nil;

    CFArrayRef windowList = CGWindowListCreate(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    NSArray <NSDictionary *> *descriptions = (__bridge id)CGWindowListCreateDescriptionFromArray(windowList);

    NSArray <NSDictionary <NSString *, id> *> *wallpaperWindows = [descriptions filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(%K CONTAINS %@ OR %K CONTAINS %@) AND %K == %@", kCGWindowName, @"Wallpaper", kCGWindowName, @"Desktop Picture", kCGWindowOwnerName, @"Dock"]];

    CGDirectDisplayID displayID = screen.displayID.unsignedIntValue;
    CGRect displayBounds = CGDisplayBounds(displayID);

    NSDictionary *wallpaperWindow = nil;

    for (NSDictionary *windowDict in wallpaperWindows) {
        NSDictionary *boundsDict = windowDict[(__bridge id)kCGWindowBounds];
        if (!boundsDict) continue;
        CGRect windowRect = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict, &windowRect)) continue;

        if (CGRectContainsPoint(displayBounds, windowRect.origin)) {
            wallpaperWindow = windowDict;
            break;
        }
    }

    if (!wallpaperWindow) return nil;

    NSNumber *windowNumber = [wallpaperWindow objectForKey:(__bridge id)kCGWindowNumber];
    if (!windowNumber) return nil;

    CGImageRef cgImage = CGWindowListCreateImage(displayBounds, kCGWindowListOptionIncludingWindow, (CGWindowID)[windowNumber unsignedIntValue], kCGWindowImageDefault);
    if (!cgImage) return nil;

    return [[NSImage alloc] initWithCGImage:cgImage size:NSMakeSize(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage))];
}

@end

@implementation NSScreen (DisplayInfo)

- (NSNumber*)displayID
{
    return [[self deviceDescription] valueForKey:@"NSScreenNumber"];
}

@end
