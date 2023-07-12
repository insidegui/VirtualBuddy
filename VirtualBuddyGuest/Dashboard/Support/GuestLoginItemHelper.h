@import Foundation;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kGuestAppLaunchAtLoginHelperBundleID;

@interface GuestLoginItemHelper : NSObject

+ (CFArrayRef _Nullable)fetchAllLoginItems;

@end

NS_ASSUME_NONNULL_END
