#import <VirtualInstallation/Constants.h>

NSString * const kVirtualInstallationSubsystem = @"codes.rambo.VirtualInstallation";

NSString * const kVirtualInstallationServiceName = VI_SERVICE_BUNDLE_IDENTIFIER;

NSString * const kVirtualInstallationProjectVersionForCodeSigningRequirements = CURRENT_PROJECT_VERSION_FOR_CODE_REQUIREMENTS;
NSString * const kVirtualInstallationTeamIDForCodeSigningRequirements = TEAM_ID_FOR_CODE_REQUIREMENTS;
NSString * const kVirtualBuddyBundleID = VIRTUALBUDDY_BUNDLE_ID;

NSString * const kVirtualInstallationUnifiedLogPredicate = @"senderImagePath contains 'VirtualInstallation' OR (process contains 'VirtualInstallationService' AND senderImagePath contains 'MobileDevice')";
