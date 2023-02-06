#import "GuestLoginItemHelper.h"

@import ServiceManagement;

NSString *const kGuestAppLaunchAtLoginHelperBundleID = GUEST_LAUNCH_AT_LOGIN_HELPER_BUNDLE_ID;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation GuestLoginItemHelper

+ (CFArrayRef _Nullable)fetchAllLoginItems
{
    return SMCopyAllJobDictionaries(kSMDomainUserLaunchd);
}

@end

#pragma clang diagnostic pop
