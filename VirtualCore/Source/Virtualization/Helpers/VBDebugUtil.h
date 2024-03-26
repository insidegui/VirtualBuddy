#if DEBUG

#import <Foundation/Foundation.h>

@class VZVirtualMachine;

NS_ASSUME_NONNULL_BEGIN

/// This is used to stop VirtualBuddy in the debugger at specific points in a VM's lifecycle,
/// so that exploring Virtualization internals can be done in Objective-C.
@interface VBDebugUtil : NSObject

+ (void)debugVirtualMachineBeforeStart:(VZVirtualMachine *_Nonnull)vm;
+ (void)debugVirtualMachineAfterStart:(VZVirtualMachine *_Nonnull)vm;

@end

NS_ASSUME_NONNULL_END

#endif
