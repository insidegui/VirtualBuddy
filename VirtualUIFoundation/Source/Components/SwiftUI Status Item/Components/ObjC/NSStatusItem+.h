#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSStatusItem (VUIAdditions)

@property (nonatomic, strong) NSView *__nullable vui_contentView;

- (void)vui_disableVibrancy;

@property (class, nonatomic, readonly) CGFloat vui_idealPadding;

+ (void)vui_drawMenuBarHighlightInView:(NSView *)view
                           highlighted:(BOOL)isHighlighted
                                 inset:(CGFloat)insetAmount;

@end

NS_ASSUME_NONNULL_END
