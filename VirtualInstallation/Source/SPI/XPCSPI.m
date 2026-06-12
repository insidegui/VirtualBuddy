#import <VirtualInstallation/XPCSPI.h>
#import <VirtualInstallation/Constants.h>

@interface NSXPCConnection (Private)

@property (readonly) xpc_connection_t _xpcConnection;

@end

extern void xpc_connection_set_instance(xpc_connection_t connection, uuid_t instance) WEAK_IMPORT_ATTRIBUTE;

@implementation NSXPCConnection (SPIHelper)

+ (BOOL)__vi_has_xpc_connection_set_instance
{
    static dispatch_once_t onceToken;
    static BOOL _has;
    dispatch_once(&onceToken, ^{
        _has = xpc_connection_set_instance != NULL;
    });
    return _has;
}

+ (BOOL)__vi_has_NSXPCConnection_xpcConnection_property
{
    static dispatch_once_t onceToken;
    static BOOL _has;
    dispatch_once(&onceToken, ^{
        _has = [NSXPCConnection instancesRespondToSelector:@selector(_xpcConnection)];
    });
    return _has;
}

+ (BOOL)__vi_safeSetInstanceUUID:(NSUUID *)uuid onConnection:(NSXPCConnection *)connection error:(NSError **)outError
{
    if (![NSXPCConnection __vi_has_xpc_connection_set_instance]) {
        if (outError) *outError = [NSError errorWithDomain:kVirtualInstallationSubsystem
                                                      code:1
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Current system is missing xpc_connection_set_instance function"}];
        return NO;
    }
    if (![NSXPCConnection __vi_has_NSXPCConnection_xpcConnection_property]) {
        if (outError) *outError = [NSError errorWithDomain:kVirtualInstallationSubsystem
                                                      code:2
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Current system is missing -[NSXPCConnection _xpcConnection]"}];
        return NO;
    }

    xpc_connection_t conn = connection._xpcConnection;
    if (conn == NULL) {
        if (outError) *outError = [NSError errorWithDomain:kVirtualInstallationSubsystem
                                                      code:3
                                                  userInfo:@{NSLocalizedDescriptionKey: @"NULL xpc_connection_t"}];
        return NO;
    }

    uuid_t uuidBytes;
    [uuid getUUIDBytes:uuidBytes];

    xpc_connection_set_instance(conn, uuidBytes);

    return YES;
}

- (BOOL)__vi_safeSetInstanceUUID:(NSUUID *)uuid error:(NSError **)outError
{
    return [NSXPCConnection __vi_safeSetInstanceUUID:uuid onConnection:self error:outError];
}

@end
