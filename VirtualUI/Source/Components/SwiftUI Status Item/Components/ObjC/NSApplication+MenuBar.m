#import "NSApplication+MenuBar.h"

@import os.log;

#import <dlfcn.h>

#import <VirtualUI/VirtualUI-Swift.h>

Boolean __vui_softLinkHIMenuBarRequestVisibility(Boolean visibility, Boolean *outAlreadyInState, void (^completion)(void));

@implementation NSApplication (MenuBar)

+ (os_log_t)__vui_menuBarLog
{
    static os_log_t _log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _log = os_log_create([[_VirtualUIConstantsObjC subsystemName] UTF8String], "NSApplication+VUIMenuBar");
    });
    return _log;
}

- (void)__vui_setMenuBarVisible:(BOOL)visible
{
    os_log_t log = [NSApplication __vui_menuBarLog];

    os_log_debug(log, "Set menu bar visibility to %{public}d", visible);

    Boolean result = false;
    Boolean alreadyInState = false;

    result = __vui_softLinkHIMenuBarRequestVisibility(visible, &alreadyInState, ^{ });

    os_log_debug(log, "Set menu bar visibility result: %{public}d, already in state: %{public}d", visible, alreadyInState);
}

@end

typedef Boolean (*_VUIHIMenuBarRequestVisibilityPtr)(Boolean visibility, Boolean *outAlreadyInState, void (^completion)(void));

Boolean __vui_softLinkHIMenuBarRequestVisibility(Boolean visibility, Boolean *outAlreadyInState, void (^completion)(void)) {
    static _VUIHIMenuBarRequestVisibilityPtr fnptr;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/Frameworks/Carbon.framework/Versions/Current/Carbon", RTLD_NOW);
        if (!handle) {
            __assert("Couldn't load Carbon dylib", __FILE__, __LINE__);
            return;
        }

        void *fn = dlsym(handle, "_HIMenuBarRequestVisibility");
        if (!fn) {
            __assert("Couldn't load _HIMenuBarRequestVisibility symbol", __FILE__, __LINE__);
            return;
        }

        fnptr = (_VUIHIMenuBarRequestVisibilityPtr)fn;
    });

    if (!fnptr) return false;

    return fnptr(visibility, outAlreadyInState, completion);
}
