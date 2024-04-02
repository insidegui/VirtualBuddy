#if DEBUG

#import "VBDebugUtil.h"

@import Virtualization;

#import <VirtualCore/VirtualizationPrivate.h>

@implementation VBDebugUtil

/// Runs in debug builds when VM is about to be started.
+ (void)debugVirtualMachineBeforeStart:(VZVirtualMachine *_Nonnull)vm
{
    NSLog(@"Debug virtual machine before start: %@", vm);
    return;
}

/// Runs in debug builds right after the VM has been started.
+ (void)debugVirtualMachineAfterStart:(VZVirtualMachine *_Nonnull)vm
{
    NSLog(@"Debug virtual machine after start: %@", vm);
    
    __weak typeof(vm) weakVM = vm;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!weakVM) return;

        [self debugVirtualMachineAfterStartWithDelay:weakVM];
    });
}

/// Runs in debug builds several seconds after the VM has been started (likely after it's finished booting up).
+ (void)debugVirtualMachineAfterStartWithDelay:(VZVirtualMachine *_Nonnull)vm
{
    NSLog(@"Debug virtual machine after start with delay: %@", vm);
    return;
}

@end

#endif
