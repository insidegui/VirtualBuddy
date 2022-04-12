//
//  VBObjCHookingPoint.m
//  VirtualCore
//
//  Created by Guilherme Rambo on 11/04/22.
//

#import "VBObjCHookingPoint.h"

@import Virtualization;

@interface VBObjCHookingPoint ()

@property (weak) VZVirtualMachine *vm;

@end

@implementation VBObjCHookingPoint

- (instancetype)initWithVM:(VZVirtualMachine *)vm
{
    self = [super init];
    self.vm = vm;
    return self;
}

- (void)hook
{
    return;
}

@end
