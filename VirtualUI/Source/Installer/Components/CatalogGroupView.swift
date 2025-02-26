import SwiftUI
import VirtualCore
import VirtualCatalog

struct CatalogGroupView: View {
    static var cornerRadius: CGFloat { 14 }

    var group: ResolvedCatalogGroup

    var thumbnail: CatalogGraphic.Thumbnail { group.darkImage.thumbnail }

    var body: some View {
        ZStack {
            RemoteImage(
                url: thumbnail.url,
                blurHash: thumbnail.blurHash,
                blurHashSize: CGSize(width: 5, height: 5)
            )

            Text(group.name)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .shadow(color: .black.opacity(0.2), radius: 3)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, 22)
        }
        .clipShape(shape)
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }
}

#if DEBUG
#Preview {
    CatalogGroupView(group: ResolvedCatalog.previewMac.groups[0])
        .frame(width: 320, height: 180)
        .padding(64)
}
#endif
