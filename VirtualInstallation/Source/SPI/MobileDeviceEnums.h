#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(int, AMRestorableDeviceEvent) {
    AMRestorableDeviceEventFound,
    AMRestorableDeviceEventLost
};

typedef NS_ENUM(int, AMRestorableDeviceState) {
    kAMRestorableDeviceStateUnknown,
    kAMRestorableDeviceStateDFU,
    kAMRestorableDeviceStateRecovery,
    kAMRestorableDeviceStateRestoreOS,
    kAMRestorableDeviceStateBootedOS
};

typedef NS_ENUM(int, AMRestorableDeviceFusing) {
    AMRestorableDeviceFusingUnknown,
    AMRestorableDeviceFusingDevelopment,
    AMRestorableDeviceFusingProduction,
    AMRestorableDeviceFusingInsecure,
};

typedef NS_ENUM(uint, AMRestorableDeviceClass) {
    AMRestorableDeviceClassUnknown        = 0,
    AMRestorableDeviceClassiPhone         = 1 << 0,
    AMRestorableDeviceClassiPad           = 1 << 1,
    AMRestorableDeviceClassWatch          = 1 << 2,
    AMRestorableDeviceClassTV             = 1 << 3,
    AMRestorableDeviceClassBridge         = 1 << 4,
    AMRestorableDeviceClassAudioAccessory = 1 << 5,
    AMRestorableDeviceClassiPod           = 1 << 6,
    AMRestorableDeviceClassMac            = 1 << 7,
    AMRestorableDeviceClassDarwin         = 1 << 8,
    AMRestorableDeviceClassVision         = 1 << 9,
    AMRestorableDeviceClassComputeModule  = 1 << 10,
};
