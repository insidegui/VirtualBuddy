//
//  GuestTypePicker.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 06/03/23.
//

import SwiftUI
import VirtualCore

extension VBGuestType {
    var name: String {
        switch self {
        case .mac:
            return "macOS"
        case .linux:
            return "Linux"
        }
    }

    var icon: Image { Image("VBGuestType/\(rawValue)", bundle: .virtualUI) }
}

struct GuestTypePicker: View {

    static var buttonRadius: Double { 24 }
    static var selectionIndicatorID = "SelectionIndicator"

    @Binding var selection: VBGuestType

    private var previousMethod: VBGuestType? { VBGuestType.allCases.previous(from: selection) }

    private var nextMethod: VBGuestType? { VBGuestType.allCases.next(from: selection) }

    @Namespace
    private var selectionIndicator

    var body: some View {
        HStack(spacing: 16) {
            ForEach(VBGuestType.supportedByHost) { type in
                GuestTypeItemView(
                    type: type,
                    isSelected: selection == type,
                    selectionIndicator: selectionIndicator
                )
                .onTapGesture {
                    selection = type
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.buttonRadius, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .blendMode(.plusLighter)
                .opacity(0.6)
                .matchedGeometryEffect(id: Self.selectionIndicatorID, in: selectionIndicator, isSource: false)
                .animation(.snappy, value: selection)
        }
        .accessibilityRepresentation {
            Picker(selection: $selection) {
                ForEach(VBGuestType.allCases) { type in
                    Text(type.name)
                        .tag(type)
                }
            } label: { }
        }
        .keyboardNavigation { direction in
            if direction == .right {
                guard let nextMethod else { return }
                selection = nextMethod
            } else if direction == .left {
                guard let previousMethod else { return }
                selection = previousMethod
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct GuestTypeItemView: View {

    let type: VBGuestType
    let isSelected: Bool
    let selectionIndicator: Namespace.ID

    init(type: VBGuestType, isSelected: Bool, selectionIndicator: Namespace.ID) {
        self.type = type
        self.isSelected = isSelected
        self.selectionIndicator = selectionIndicator
    }

    var lineWidth: CGFloat { isSelected ? 2 : 1 }

    var body: some View {
        VStack(spacing: 18) {
            type.icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 80)

            Text(type.name)
        }
        .shadow(color: .black.opacity(0.5), radius: 1, x: 0.5, y: 0.5)
        .padding()
        .multilineTextAlignment(.center)
        .font(.system(size: 24, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 260)
        .background {
            ZStack {
//                if isSelected {
//                    Rectangle().foregroundStyle(Material.thick)
//
//                    Color.accentColor
//                        .blendMode(.plusLighter)
//                        .opacity(0.2)
//                } else {
                    Rectangle().foregroundStyle(Material.thin)
//                }
            }
            .clipShape(shape)
        }
        .chromeBorder(shape: shape, shadowEnabled: false, highlightIntensity: 0.5)
        .overlay {
            if isSelected {
                Rectangle()
                    .opacity(0)
                    .matchedGeometryEffect(id: GuestTypePicker.selectionIndicatorID, in: selectionIndicator, isSource: true)
            }
        }
    }

    private var borderColor: Color {
        isSelected ? .accentColor : .primary.opacity(0.2)
    }

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: GuestTypePicker.buttonRadius, style: .continuous)
    }

}

#if DEBUG
@available(macOS 14.0, *)
#Preview {
    @Previewable @State var selection: VBGuestType = .mac

    GuestTypePicker(selection: $selection)
        .padding(22)
        .frame(width: VMInstallationWizard.maxContentWidth, height: 600)
        .background(BlurHashFullBleedBackground(.virtualBuddyBackground))
}
#endif
