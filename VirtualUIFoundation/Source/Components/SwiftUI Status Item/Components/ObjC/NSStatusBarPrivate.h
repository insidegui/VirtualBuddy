@import Cocoa;

NS_ASSUME_NONNULL_BEGIN

@interface NSStatusBar (Private)

@property (nonatomic, readonly) CGFloat contentPadding;

- (void)drawBackgroundInRect:(NSRect *)rect inView:(NSView *)view highlight:(BOOL)highlight;

@end

@interface NSStatusItem (Private)

- (void)setAllowsVibrancy:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END
