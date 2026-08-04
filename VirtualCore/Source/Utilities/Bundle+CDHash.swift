import Foundation
import Security

public extension Bundle {
    /// Returns the CDHash from the code signature of the bundle's executable.
    func executableCDHash() throws -> Data {
        guard let executableURL else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileNoSuchFileError,
                userInfo: [NSURLErrorKey: bundleURL]
            )
        }

        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(
            executableURL as CFURL,
            SecCSFlags(),
            &staticCode
        )

        guard status == errSecSuccess, let staticCode else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSURLErrorKey: executableURL]
            )
        }

        var signingInformation: CFDictionary?
        status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(),
            &signingInformation
        )

        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSURLErrorKey: executableURL]
            )
        }

        guard
            let signingInformation,
            let cdHash = (signingInformation as NSDictionary)[kSecCodeInfoUnique] as? Data
                else {
            /// The executable exists but has no code signature/CDHash.
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(errSecCSUnsigned),
                userInfo: [NSURLErrorKey: executableURL]
            )
        }

        return cdHash
    }
}
