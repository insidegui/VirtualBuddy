#pragma once

#import <Foundation/Foundation.h>
#import <VirtualInstallation/MobileDeviceEnums.h>

#pragma mark Types

typedef int AMDError;

typedef struct __AMRestorableDevice *AMRestorableDeviceRef;

typedef int AMRestorableClientID;
extern const AMRestorableClientID kAMRestorableInvalidClientID WEAK_IMPORT_ATTRIBUTE;

typedef void (*AMRestorableDeviceNotificationCallback)(AMRestorableDeviceRef _Nonnull device, AMRestorableDeviceEvent event, void *_Nullable context);
typedef void (*AMRestorableDeviceProgressCallback)(AMRestorableDeviceRef _Nonnull device, CFDictionaryRef _Nonnull info, void *_Nullable context);

#pragma mark - Functions

extern AMRestorableClientID AMRestorableDeviceRegisterForNotifications(AMRestorableDeviceNotificationCallback _Nonnull callback,
                                                                       void *_Nullable context,
                                                                       CFErrorRef _Nullable *_Nonnull error) WEAK_IMPORT_ATTRIBUTE;
extern bool AMRestorableDeviceUnregisterForNotifications(AMRestorableClientID clientID) WEAK_IMPORT_ATTRIBUTE;

extern AMRestorableDeviceClass AMRestorableDeviceGetDeviceClass(AMRestorableDeviceRef _Nonnull device) WEAK_IMPORT_ATTRIBUTE;
extern uint64_t AMRestorableDeviceGetECID(AMRestorableDeviceRef _Nonnull device) WEAK_IMPORT_ATTRIBUTE;
extern AMRestorableDeviceState AMRestorableDeviceGetState(AMRestorableDeviceRef _Nonnull device) WEAK_IMPORT_ATTRIBUTE;

extern BOOL AMRestorableSetGlobalLogFileURL(CFURLRef _Nonnull url) WEAK_IMPORT_ATTRIBUTE;
extern BOOL AMRestorableDeviceSetLogFileURL(AMRestorableDeviceRef _Nonnull device, CFURLRef _Nonnull url, CFStringRef _Nonnull type) WEAK_IMPORT_ATTRIBUTE;
extern void AMRestorableDeviceRestore(AMRestorableDeviceRef _Nonnull device, CFDictionaryRef _Nonnull options, AMRestorableDeviceProgressCallback _Nonnull callback, void *_Nullable refCon) WEAK_IMPORT_ATTRIBUTE;
extern CFStringRef _Nonnull AMRLocalizedCopyStringForAMROperation(int operation) CF_RETURNS_RETAINED WEAK_IMPORT_ATTRIBUTE;
