#pragma once

#import <Foundation/Foundation.h>

#import <VirtualInstallation/MobileDeviceSPI.h>

/// Waits for the specified device to be connected.
/// - Parameters:
///   - ecid: The ECID of the device to wait for.
///   - state: The state the device needs to be in. Specify `kAMRestorableDeviceStateUnknown` if you don't care about the state.
///   - timeoutInMilliseconds: The maximum amount of time in milliseconds to wait for the device.
///
/// This blocks the current queue and waits for a restorable device with the specified ECID and state to show up.
/// If state is set to `kAMRestorableDeviceStateUnknown`, this returns as soon as the device shows up, in any state.
///
/// Returns the device once found in the specified state.
/// If more than `timeoutInMilliseconds` elapses and the device is not found in the specified state, returns `nil`.
///
/// - note: Because this function blocks until the device is found or it times out, you should not call it from the main queue.
AMRestorableDeviceRef _Nullable VIWaitForDeviceWithECID(uint64_t ecid, AMRestorableDeviceState state, int timeoutInMilliseconds);
