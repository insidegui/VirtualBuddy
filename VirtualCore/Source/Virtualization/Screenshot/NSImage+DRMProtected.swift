import Cocoa
import BuddyKit
import Vision

@available(macOS 15.0, *)
extension NSImage {
    /// This is kinda silly.
    ///
    /// All this does is it attempts to detect the string "DRM Protected" inside of a thumbnail image.
    /// This is to work around a bug that happened in macOS 26 where screenshots used for thumbnails
    /// would display a "DRM Protected Video" message with a black background.
    ///
    /// Some users ended up with these bad thumbnails in their library and with the new background hash
    /// thumbnails I didn't want them to get a black background with a white blurry blob as their VM thumbnail.
    ///
    /// See: https://github.com/insidegui/VirtualBuddy/discussions/533
    func detectDRMProtectedVideoBug() async -> Bool {
        guard let cgImage else { return false }

        var request = RecognizeTextRequest()
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = [.init(components: .init(languageCode: .english, script: nil, region: nil))]
        request.recognitionLevel = .fast
        request.minimumTextHeightFraction = 0.05

        guard let observations = try? await request.perform(on: cgImage) else { return false }

        return observations.contains(where: { $0.text.localizedCaseInsensitiveContains("DRM Protected") })
    }
}

@available(macOS 15.0, *)
private extension RecognizedTextObservation {
    var text: String {
        topCandidates(1).first?.string ?? ""
    }
}
