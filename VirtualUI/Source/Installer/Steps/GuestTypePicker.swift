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

    @Binding var selection: VBGuestType

    @FocusState private var isFocused: Bool

    private var selectionIndex: Int { VBGuestType.allCases.firstIndex(of: selection) ?? 0 }

    private var previousMethod: VBGuestType? {
        guard selectionIndex > 0 else { return nil }
        return VBGuestType.allCases[selectionIndex - 1]
    }

    private var nextMethod: VBGuestType? {
        guard selectionIndex < VBGuestType.allCases.count - 1 else { return nil }
        return VBGuestType.allCases[selectionIndex + 1]
    }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(VBGuestType.supportedByHost) { type in
                GuestTypeItemView(
                    type: type,
                    isSelected: selection == type
                )
                .onTapGesture {
                    selection = type
                }
            }
        }
        .accessibilityRepresentation {
            Picker(selection: $selection) {
                ForEach(VBGuestType.allCases) { type in
                    Text(type.name)
                        .tag(type)
                }
            } label: { }
        }
        .overlay {
            /// Horrible hack to hide the focus ring while still allowing for keyboard navigation.
            Rectangle()
                .frame(width: 0, height: 0)
                .opacity(0)
                .focusable(true)
                .focused($isFocused)
                .onMoveCommand { direction in
                    if direction == .right {
                        guard let nextMethod else { return }
                        selection = nextMethod
                    } else if direction == .left {
                        guard let previousMethod else { return }
                        selection = previousMethod
                    }
                }
        }
        .onAppearOnce {
            isFocused = true
        }
    }

}

struct GuestTypeItemView: View {

    let type: VBGuestType
    let isSelected: Bool

    var lineWidth: CGFloat { isSelected ? 2 : 1 }

    var body: some View {
        VStack(spacing: 24) {
            type.icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 80)
            Text(type.name)
        }
        .foregroundColor(isSelected ? .accentColor : .secondary)
        .padding()
        .multilineTextAlignment(.center)
        .font(.system(size: 22, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .aspectRatio(1, contentMode: .fit)
        .overlay(shape.stroke(borderColor, style: StrokeStyle(lineWidth: lineWidth)))
        .materialBackground(.menu, blendMode: .withinWindow, state: isSelected ? .active : .inactive, in: shape)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 0)
    }

    private var borderColor: Color {
        isSelected ? .accentColor : .primary.opacity(0.2)
    }

    private var shape: some Shape {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

}

#if DEBUG
struct GuestTypePicker_Previews: PreviewProvider, View {
    @State private var selection: VBGuestType = .mac

    static var previews: some View {
        GuestTypePicker_Previews()
    }

    var body: some View {
        GuestTypePicker(selection: $selection)
            .padding(22)
            .frame(width: 600, height: 600)
    }
}
#endif
