#if DEBUG
import SwiftUI

public extension View {
    func previewWallpaper(scale: CGFloat = 1.0, overlay: () -> some View = { EmptyView() }) -> some View {
        background(BlurHashFullBleedBackground(blurHash: .virtualBuddyBackground))
    }
}
#endif
