import SwiftUI

struct MaskProgressView<Mask: View, Foreground: ShapeStyle, Background: ShapeStyle>: View {
    var progress: Double
    var background: Background
    var foreground: Foreground
    @ViewBuilder var mask: (Double) -> Mask

    var body: some View {
        ZStack {
            let content = mask(progress)

            content
                .foregroundStyle(background)

            content
                .foregroundStyle(foreground)
                .mask {
                    GeometryReader { proxy in
                        Rectangle().fill(.white)
                            .frame(width: proxy.size.width * progress, alignment: .leading)
                    }
                }
        }
    }
}
