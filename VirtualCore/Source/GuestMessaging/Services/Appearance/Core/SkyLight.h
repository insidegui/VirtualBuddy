#import <Foundation/Foundation.h>

extern int SLSGetAppearanceThemeLegacy(void) WEAK_IMPORT_ATTRIBUTE;
extern void SLSSetAppearanceThemeLegacy(int) WEAK_IMPORT_ATTRIBUTE;

static BOOL VBCheckSkyLightSPI(void)
{
    static dispatch_once_t onceToken;
    static BOOL _available;
    dispatch_once(&onceToken, ^{
        if (SLSGetAppearanceThemeLegacy == NULL) {
            _available = NO;
            return;
        }
        if (SLSSetAppearanceThemeLegacy == NULL) {
            _available = NO;
            return;
        }
        _available = YES;
    });
    return _available;
}
