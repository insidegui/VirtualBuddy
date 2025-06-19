//
//  CGImage+FullyTransparent.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 19/06/25.
//

import Cocoa
import CoreImage
import CoreImage.CIFilterBuiltins

private let transparentCheckContext = CIContext(options: [.workingColorSpace: NSNull()])

extension CGImage {
    /// Returns `true` if the image is fully transparent or has width and height equal to zero.
    func isFullyTransparent() -> Bool {
        /// Zero size image is considered fully transparent.
        guard width > 0, height > 0 else { return true }

        /// If image has no alpha, then it can't be fully transparent.
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }

        let ciImage = CIImage(cgImage: self)

        let filter = CIFilter.areaMaximumAlpha()
        filter.inputImage = ciImage
        filter.extent = ciImage.extent

        guard let reduced = filter.outputImage else {
            assertionFailure("Error reducing image area maximum alpha")
            return false
        }

        var alpha: UInt32 = 0

        transparentCheckContext
            .render(
                reduced,
                toBitmap: &alpha,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .A8,
                colorSpace: nil
            )

        return alpha == 0
    }

    static func load(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.coderInvalidValue)
        }

        return cgImage
    }

    static func load(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CocoaError(.coderValueNotFound)
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.coderInvalidValue)
        }

        return cgImage
    }
}
