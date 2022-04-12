@import Cocoa;
@import ObjectiveC.runtime;

//extern CGRect GetDaisyBounds(void);

#define DYLD_INTERPOSE(_replacment,_replacee) \
   __attribute__((used)) static struct{ const void* replacment; const void* replacee; } _interpose_##_replacee \
            __attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacment, (const void*)(unsigned long)&_replacee };

@interface VirtualBuddyNSWindowOverrides: NSWindow
@end

@implementation VirtualBuddyNSWindowOverrides
//
//+ (void)load
//{
//    Class saC = objc_getClass("_NSSafeApertureCompatibilityManager");
//    Method m = class_getClassMethod([saC class], NSSelectorFromString(@"_updateSafeApertureCompatibilityMode:withURLResourceKey:forMode:fromDataSource:"));
//    Method m2 = class_getInstanceMethod([self class], NSSelectorFromString(@"_updateSafeApertureCompatibilityMode:withURLResourceKey:forMode:fromDataSource:"));
//    method_exchangeImplementations(m, m2);
//}
//
//+(void)_updateSafeApertureCompatibilityMode:(id)arg2 withDefaultsKey:(id)arg3 forMode:(id)arg4 fromDataSource:(id)arg5
//{
//
//}

@end
