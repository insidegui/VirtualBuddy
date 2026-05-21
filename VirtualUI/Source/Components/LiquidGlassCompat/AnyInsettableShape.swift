import SwiftUI

/// This is a naive implementation that may not work with every type of shape.
public struct AnyInsettableShape: InsettableShape {
    private var shape: AnyShape
    private var inset: CGFloat = 0

    private init(shape: AnyShape, inset: CGFloat) {
        self.shape = shape
        self.inset = inset
    }

    public init(_ shape: some InsettableShape) {
        self.init(shape: AnyShape(shape), inset: 0)
    }

    public nonisolated func path(in rect: CGRect) -> Path {
        let path = shape.path(in: rect.insetBy(dx: inset, dy: inset))
        return path
    }

    public nonisolated func inset(by amount: CGFloat) -> some InsettableShape {
        AnyInsettableShape(shape: shape, inset: amount)
    }
}
