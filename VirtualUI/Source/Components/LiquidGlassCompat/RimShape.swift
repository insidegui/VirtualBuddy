import SwiftUI

/// A shape that describes a stroked rim of its base shape.
///
/// Use this shape to wrap another SwiftUI `Shape` when you need to obtain a shape
/// that describes the stroke around the provided shape with a given thickness.
///
/// The returned shape can be used for filling, clipping, masking, blending, or any other operation that uses a shape.
///
/// > Tip: Use `InsettableShape.rim(thickness:)` to conveniently get a ``RimShape`` from an existing `Shape` instance.
struct RimShape<Base: InsettableShape>: InsettableShape {
    typealias InsetShape = Self

    var base: Base
    var thickness: CGFloat
    private var inset: CGFloat = 0

    init(base: Base, thickness: CGFloat = 1) {
        self.base = base
        self.thickness = thickness
    }

    nonisolated func inset(by amount: CGFloat) -> InsetShape {
        var mself = self
        mself.inset = amount
        return mself
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let outer = base.inset(by: inset).path(in: rect)
        let inner = base.inset(by: inset + thickness).path(in: rect)

        return outer.subtracting(inner)
    }
}

extension InsettableShape {

    /// Create a shape describing the stroked rim of this shape.
    /// - Parameter thickness: The thickness of the stroke.
    /// - Returns: A ``RimShape`` that uses this shape as its base shape.
    func rim(thickness: CGFloat = 1) -> RimShape<Self> {
        RimShape(base: self, thickness: thickness)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Fill") {
    Capsule(style: .continuous)
        .rim()
        .fill(Color.red)
        .frame(width: 200, height: 100)
        .padding(32)
}

#Preview("Clip") {
    Rectangle()
        .fill(Color.green)
        .frame(width: 200, height: 200)
        .clipShape(Circle().rim())
        .padding(100)
}

#Preview("Inset") {
    Circle()
        .fill(Color.black)
        .frame(width: 200, height: 200)
        .overlay {
            Circle()
                .fill(Color.white)
                .clipShape(Circle().rim())
        }
        .padding(100)
}

#Preview("Background") {
    ZStack {
        Text("Hello, World!")
            .foregroundStyle(.pink)
            .font(.title2)
            .padding(16)
            .background(LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom), in: ContainerRelativeShape().rim(thickness: 2))
    }
    .containerShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .frame(width: 400, height: 400)
}
#endif
