#import <VirtualInstallation/Constants.h>
#import <VirtualInstallation/VIWaitForDevice.h>

NSString *RUCopyRestorableDeviceStateStringFromState(AMRestorableDeviceState state);

@import os.log;

typedef void(^VIWaitForDeviceBlock)(AMRestorableDeviceRef device, AMRestorableClientID clientID);

typedef struct {
    VIWaitForDeviceBlock callback;
    AMRestorableClientID clientID;
    dispatch_queue_t queue;
} VIWaitForDeviceContext;

void __VIWaitForDeviceEventCallback(AMRestorableDeviceRef device, AMRestorableDeviceEvent event, void *context);
void __VIInvalidateContext(VIWaitForDeviceContext context);

AMRestorableDeviceRef _Nullable VIWaitForDeviceWithECID(uint64_t ecid, AMRestorableDeviceState state, int timeoutInMilliseconds)
{
    os_log_t log = os_log_create(kVirtualInstallationSubsystem.UTF8String, "VIWaitForDevice");
    os_log_debug(log, "⏰ BEGIN wait for device %@", @(ecid));

    __block AMRestorableDeviceRef outDevice = NULL;
    __block BOOL finalized = NO;

    NSString *label = [NSString stringWithFormat:@"WaitForDevice(%@)", @(ecid)];
    dispatch_queue_t queue = dispatch_queue_create(label.UTF8String, dispatch_queue_attr_make_with_qos_class(NULL, QOS_CLASS_USER_INTERACTIVE, 0));
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    VIWaitForDeviceBlock callback = ^(AMRestorableDeviceRef device, AMRestorableClientID cid) {
        if (finalized) return;
        if (AMRestorableDeviceGetECID(device) != ecid) return;

        AMRestorableDeviceState deviceState = AMRestorableDeviceGetState(device);
        if (state != kAMRestorableDeviceStateUnknown && deviceState != state) {
            os_log_info(log, "Found device %@, but its state is %@ instead of %@. Keep waiting...", @(ecid), RUCopyRestorableDeviceStateStringFromState(deviceState), RUCopyRestorableDeviceStateStringFromState(state));
            return;
        }

        finalized = YES;

        os_log_info(log, "Found target device %@ with state %@", @(ecid), RUCopyRestorableDeviceStateStringFromState(deviceState));

        outDevice = device;

        dispatch_async(queue, ^{
            dispatch_semaphore_signal(sema);
        });
    };

    __block VIWaitForDeviceContext context = {
        callback,
        kAMRestorableInvalidClientID,
        queue
    };

    dispatch_async(queue, ^{
        CFErrorRef error;
        context.clientID = AMRestorableDeviceRegisterForNotifications(__VIWaitForDeviceEventCallback, (void *)&context, &error);

        if (context.clientID == kAMRestorableInvalidClientID) {
            os_log_fault(log, "Error registering for restorable device notifications. %{public}@", error);
            dispatch_semaphore_signal(sema);
        }
    });

    intptr_t result = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutInMilliseconds * NSEC_PER_MSEC)));

    if (result == 0) {
        os_log_debug(log, "⏰ END wait for device %@ with %@", @(ecid), [NSString stringWithFormat:@"%@", outDevice]);
    } else {
        os_log_error(log, "⏰ END wait for device %@: timed out after %dms", @(ecid), timeoutInMilliseconds);
    }

    dispatch_async(queue, ^{
        __VIInvalidateContext(context);
    });

    return outDevice;
}

void __VIWaitForDeviceEventCallback(AMRestorableDeviceRef device, AMRestorableDeviceEvent event, void *context)
{
    if (!context) return;

    if (event == AMRestorableDeviceEventFound) {
        VIWaitForDeviceContext *deviceContext = (VIWaitForDeviceContext *)context;

        assert(deviceContext != NULL);
        if (!deviceContext) return;

        deviceContext->callback(device, deviceContext->clientID);
    }
}

void __VIInvalidateContext(VIWaitForDeviceContext context)
{
    if (context.clientID == kAMRestorableInvalidClientID) return;

    dispatch_async(context.queue, ^{
        AMRestorableDeviceUnregisterForNotifications(context.clientID);
    });
}

NSString *RUCopyRestorableDeviceStateStringFromState(AMRestorableDeviceState state)
{
    switch(state) {
    case kAMRestorableDeviceStateUnknown: return @"Unknown";
    case kAMRestorableDeviceStateDFU: return @"DFU";
    case kAMRestorableDeviceStateRecovery: return @"Recovery";
    case kAMRestorableDeviceStateRestoreOS: return @"RestoreOS";
    case kAMRestorableDeviceStateBootedOS: return @"BootedOS";
    default: return [NSString stringWithFormat:@"Unexpected state %@", @(state)];
    }
}
