#import "MobileDeviceHelper.h"

#import <VirtualInstallation/MobileDeviceSPI.h>

#define ShouldTestMobileDeviceFailure [[NSUserDefaults standardUserDefaults] boolForKey:@"VITestMobileDeviceFailure"]

#define CheckMobileDeviceSymbol( sym ) \
    if (sym == NULL) { \
        if (!ShouldTestMobileDeviceFailure) NSAssert(NO, @"MobileDevice symbol not available: " #sym); \
        _result = NO; \
        return; \
    }

@implementation MobileDeviceHelper

+ (BOOL)verifyMobileDeviceSoftLink
{
    static dispatch_once_t onceToken;
    static BOOL _result;
    dispatch_once(&onceToken, ^{
        if (ShouldTestMobileDeviceFailure) CheckMobileDeviceSymbol(NULL);

        CheckMobileDeviceSymbol(AMRestorableDeviceRegisterForNotifications);
        CheckMobileDeviceSymbol(AMRestorableDeviceUnregisterForNotifications);
        CheckMobileDeviceSymbol(&kAMRestorableInvalidClientID);
        CheckMobileDeviceSymbol(AMRestorableDeviceGetDeviceClass);
        CheckMobileDeviceSymbol(AMRestorableDeviceGetDeviceClass);
        CheckMobileDeviceSymbol(AMRestorableDeviceGetECID);
        CheckMobileDeviceSymbol(AMRestorableDeviceGetState);
        CheckMobileDeviceSymbol(AMRestorableSetGlobalLogFileURL);
        CheckMobileDeviceSymbol(AMRestorableDeviceSetLogFileURL);
        CheckMobileDeviceSymbol(AMRestorableDeviceRestore);
        CheckMobileDeviceSymbol(AMRLocalizedCopyStringForAMROperation);

        _result = YES;
    });
    return _result;
}

@end
