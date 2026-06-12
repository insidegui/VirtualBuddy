#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSXPCConnection (SPIHelper)

+ (BOOL)__vi_safeSetInstanceUUID:(NSUUID *)uuid onConnection:(NSXPCConnection *)connection error:(NSError **)outError;
- (BOOL)__vi_safeSetInstanceUUID:(NSUUID *)uuid error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
