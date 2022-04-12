//
//  VBObjCHookingPoint.h
//  VirtualCore
//
//  Created by Guilherme Rambo on 11/04/22.
//

@import Foundation;

@class VZVirtualMachine;

NS_ASSUME_NONNULL_BEGIN

/// This is just a debugging probe so that ObjC syntax can be easily used in debugging sessions.
@interface VBObjCHookingPoint : NSObject

- (instancetype)initWithVM:(VZVirtualMachine *)vm;

- (void)hook;

@end

NS_ASSUME_NONNULL_END
