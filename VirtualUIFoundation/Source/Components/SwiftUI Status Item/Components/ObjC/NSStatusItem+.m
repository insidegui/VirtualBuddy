#import "NSStatusItem+.h"

#import "NSStatusBarPrivate.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation NSStatusItem (VUIAdditions)

- (NSView *)vui_contentView
{
    return self.view;
}

- (void)setVui_contentView:(NSView *)vui_contentView
{
    self.view = vui_contentView;
}

- (void)vui_disableVibrancy
{
    if ([self respondsToSelector:@selector(setAllowsVibrancy:)]) {
        [self setAllowsVibrancy:NO];
    }
}

+ (CGFloat)vui_idealPadding
{
    if ([[NSStatusBar systemStatusBar] respondsToSelector:@selector(contentPadding)]) {
        return [[NSStatusBar systemStatusBar] contentPadding];
    } else {
        return 16.0;
    }
}

+ (void)vui_drawMenuBarHighlightInView:(NSView *)view highlighted:(BOOL)isHighlighted inset:(CGFloat)insetAmount
{
    if (!view.window || !view.superview) return;
    if (!view.window.isVisible) return;
    if (view.bounds.size.width <= 0 || view.bounds.size.height <= 0) return;

    if (![[NSStatusBar systemStatusBar] respondsToSelector:@selector(drawBackgroundInRect:inView:highlight:)]) {
        return [self __vui_drawFallbackMenuBarHighlightInView:view];
    }

    NSRect rect = NSInsetRect(view.bounds, insetAmount, 0);

    [[NSStatusBar systemStatusBar] drawBackgroundInRect:&rect inView:view highlight:isHighlighted];
}

+ (void)__vui_drawFallbackMenuBarHighlightInView:(NSView *)view
{
    [view lockFocus];
    [[[NSColor blackColor] colorWithAlphaComponent:0.1] setFill];
    NSRectFill(view.bounds);
    [view unlockFocus];
}

@end

#pragma clang diagnostic pop
