//
//  VirtualizationPrivate.h
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

@import Virtualization;

NS_ASSUME_NONNULL_BEGIN

@interface _VZFramebuffer: NSObject

- (void)takeScreenshotWithCompletionHandler:(void(^)(NSImage *__nullable screenshot, NSError *__nullable error))completion;

@end

@interface _VZGraphicsDevice: NSObject

- (NSInteger)type;
- (NSArray <_VZFramebuffer *> *)framebuffers;

@end

@interface _VZMultiTouchDeviceConfiguration: NSObject <NSCopying>
@end

@interface _VZAppleTouchScreenConfiguration: _VZMultiTouchDeviceConfiguration
@end

@interface _VZUSBTouchScreenConfiguration: _VZMultiTouchDeviceConfiguration
@end

@interface _VZVirtualMachineStartOptions: NSObject <NSSecureCoding>

@property (assign) BOOL forceDFU;
@property (assign) BOOL stopInIBootStage1;
@property (assign) BOOL stopInIBootStage2;
@property (assign) BOOL bootMacOSRecovery;

@end

@interface VZMacAuxiliaryStorage (Private)

- (NSDictionary <NSString *, id> *)_allNVRAMVariablesWithError:(NSError **)outError;
- (NSDictionary <NSString *, id> *)_allNVRAMVariablesInPartition:(NSUInteger)partition error:(NSError **)outError;
- (id __nullable)_valueForNVRAMVariableNamed:(NSString *)name error:(NSError **)arg2;
- (BOOL)_removeNVRAMVariableNamed:(NSString *)name error:(NSError **)arg2;
- (BOOL)_setValue:(id)arg1 forNVRAMVariableNamed:(NSString *)name error:(NSError **)arg3;

@end

@interface VZVirtualMachineConfiguration (Private)

@property (strong, setter=_setMultiTouchDevices:) NSArray <_VZMultiTouchDeviceConfiguration *> *_multiTouchDevices;

@end

@interface VZVirtualMachine (Private)

- (void)_startWithOptions:(_VZVirtualMachineStartOptions *__nullable)options
        completionHandler:(void (^__nonnull)(NSError * _Nullable errorOrNil))completionHandler;

- (id)_USBDevices;
- (BOOL)_canAttachUSBDevices;
- (BOOL)_canDetachUSBDevices;
- (BOOL)_canAttachUSBDevice:(id)arg1;
- (BOOL)_canDetachUSBDevice:(id)arg1;
- (BOOL)_attachUSBDevice:(id)arg1 error:(void *)arg2;
- (BOOL)_detachUSBDevice:(id)arg1 error:(void *)arg2;
- (void)_getUSBControllerLocationIDWithCompletionHandler:(void(^)(id val))arg1;

@property (nonatomic, readonly) NSArray <_VZGraphicsDevice *> *_graphicsDevices;

@end

@interface VZMacPlatformConfiguration (Private)

@property (nonatomic, assign, setter=_setProductionModeEnabled:) BOOL _isProductionModeEnabled;

- (id __nullable)_platform;

@end

@interface VZVirtualMachineView (Private)

- (void)_setDelegate:(id)delegate;

@end

NS_ASSUME_NONNULL_END
