import Foundation

/// Combination of blur hash number of components with the blur hash string itself.
///
/// This is used when a blur hash must be stored and it's possible that the number of components
/// will change between different sources of the blur hash, ensuring that clients rendering the blur hash
/// image always use the correct number of components.
public struct BlurHashToken: Hashable, Codable, Sendable, ProvidesEmptyPlaceholder {
    public var value: String
    public var size: Int

    public init(value: String, size: Int = .vbBlurHashSize) {
        self.value = value
        self.size = size
    }

    public static let empty = BlurHashToken.virtualBuddyBackground
}

public extension Int {
    /// The size of blur hash used by VirtualBuddy.
    static let vbBlurHashSize = 4
}

public extension BlurHashToken {
    /// Hardcoded VirtualBuddy orange background blur hash.
    static let virtualBuddyBackground = BlurHashToken(
        value: "U4H09BEfIY$%U7ocVcM$8%R*M}f~zwIXcArd",
        size: 4
    )
}
