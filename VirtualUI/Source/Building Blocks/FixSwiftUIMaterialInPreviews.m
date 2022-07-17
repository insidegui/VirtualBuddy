#if DEBUG

/*
This fixes SwiftUI previews not rendering translucent materials correctly by
swizzling a couple of properties on NSWindow.

Just drop into your project and add to the target being previewed (or something it links against).

Notice the #if DEBUG, so this code won't end up in release builds. It also checks for the 
XCODE_RUNNING_FOR_PREVIEWS environment variable so that it won't affect regular debug builds of the app.
*/

@import Cocoa;
@import ObjectiveC.runtime;

@interface FixSwiftUIMaterialInPreviews : NSObject

@end

@implementation FixSwiftUIMaterialInPreviews

+ (void)load
{
    NSDictionary *env = [NSProcessInfo processInfo].environment;
    BOOL isSwiftUIPreview = [env[@"XCODE_RUNNING_FOR_PREVIEWS"] boolValue];
    if (!isSwiftUIPreview) return;
    
    NSLog(@"😇 Installing fix for translucency in SwiftUI previews");
    
    Method hasKeyAppearance = class_getInstanceMethod([NSWindow class], NSSelectorFromString(@"hasKeyAppearance"));
    Method hasMainAppearance = class_getInstanceMethod([NSWindow class], NSSelectorFromString(@"hasMainAppearance"));
    Method override = class_getClassMethod([self class], @selector(__hasKeyAppearanceOverride));
    
    if (hasKeyAppearance) method_exchangeImplementations(hasKeyAppearance, override);
    if (hasMainAppearance) method_exchangeImplementations(hasMainAppearance, override);
}

+ (BOOL)__hasKeyAppearanceOverride
{
    return YES;
}

@end

#endif
