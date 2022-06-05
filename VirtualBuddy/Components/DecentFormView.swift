//
//  AirFormView.swift
//  AirUI
//
//  Created by Guilherme Rambo on 30/05/22.
//  Copyright © 2022 Guilherme Rambo. All rights reserved.
//

import SwiftUI

/// A form that aligns labels and controls in a way consistent with AirBuddy's preferences UI.
/// Contents should be instances of `AirFormControl`.
public struct DecentFormView<Content>: View where Content: View {
    
    var content: () -> Content
    var spacing: CGFloat?
    
    public init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.spacing = spacing
    }
    
    public var body: some View {
        VStack(alignment: .customLabelAlignmentGuideHorizontal, spacing: spacing) {
            content()
        }
        .labelsHidden()
    }
    
}

/// Encapsulates a control and a label to be displayed within an `AirFormView`.
/// The view can be flipped so that the label is shown to the right of the control, such as AirBuddy does with big switches in its settings UI.
public struct DecentFormControl<ContentA, ContentB>: View where ContentA: View, ContentB: View {
    
    var alignment: VerticalAlignment
    var flipped: Bool
    var leading: () -> ContentA
    var trailing: () -> ContentB
    
    public init(alignment: VerticalAlignment = .firstTextBaseline,
                flipped: Bool = false,
                @ViewBuilder control: @escaping () -> ContentB,
                @ViewBuilder label: @escaping () -> ContentA)
    {
        self.alignment = alignment
        self.flipped = flipped
        self.leading = label
        self.trailing = control
    }
    
    private var leadingContent: some View {
        leading()
            .alignedLabel(alignment)
    }
    
    private var trailingContent: some View {
        trailing()
            .alignedLabel(alignment)
    }
    
    public var body: some View {
        HStack(alignment: .customLabelAlignmentGuide) {
            Group {
                if flipped {
                    trailingContent
                } else {
                    leadingContent
                }
            }
            .trailingAlignedLabel()

            if flipped {
                leadingContent
            } else {
                trailingContent
            }
        }
    }
    
}

/// A placeholder view that does not show any content on screen and can be used
/// as the label in an `AirFormControl` where alignment of the control is desired,
/// but no label should be shown.
public struct AirFormHiddenLabel: View {
    public init() { }
    
    public var body: some View {
        Text(String("_"))
            .opacity(0)
            .accessibilityHidden(true)
    }
}

public extension DecentFormControl where ContentA == AirFormHiddenLabel {
    
    init(alignment: VerticalAlignment = .firstTextBaseline,
                @ViewBuilder control: @escaping () -> ContentB)
    {
        self.init(alignment: alignment, flipped: false, control: control, label: { AirFormHiddenLabel() })
    }
    
}

public extension View {
    
    func alignedLabel(_ alignment: VerticalAlignment = .firstTextBaseline) -> some View {
        alignmentGuide(.customLabelAlignmentGuide, computeValue: { $0[alignment] })
    }
    
    func trailingAlignedLabel() -> some View {
        alignmentGuide(.customLabelAlignmentGuideHorizontal, computeValue: { $0[.trailing] })
    }
    
}

public extension VerticalAlignment {
    private struct CustomLabelAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.bottom]
        }
    }

    static let customLabelAlignmentGuide = VerticalAlignment(
        CustomLabelAlignment.self
    )
}

public extension HorizontalAlignment {
    private struct CustomLabelAlignmentHorizontal: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.trailing]
        }
    }

    static let customLabelAlignmentGuideHorizontal = HorizontalAlignment(
        CustomLabelAlignmentHorizontal.self
    )
}
