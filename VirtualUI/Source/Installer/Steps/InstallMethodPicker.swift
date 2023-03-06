//
//  InstallMethodPicker.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import SwiftUI
import VirtualCore

enum InstallMethod: String, Identifiable, CaseIterable {
    var id: RawValue { rawValue }

    case localFile
    case remoteOptions
    case remoteManual

    func description(for type: VBGuestType) -> String {
        switch self {
            case .localFile:
            switch type {
            case .mac:
                return "Open custom IPSW file from local storage"
            case .linux:
                return "Open custom ISO file from local storage"
            }
            case .remoteOptions:
                return "Download \(type.name) installer from a list of options"
            case .remoteManual:
                return "Download \(type.name) installer from a custom URL"
        }
    }

    var imageName: String {
        switch self {
            case .localFile:
                return "folder.fill"
            case .remoteOptions:
                return "square.and.arrow.down.fill"
            case .remoteManual:
                return "text.cursor"
        }
    }
}

struct InstallMethodPicker: View {

    var guestType: VBGuestType
    @Binding var selection: InstallMethod

    @FocusState private var isFocused: Bool

    private var selectionIndex: Int { InstallMethod.allCases.firstIndex(of: selection) ?? 0 }

    private var previousMethod: InstallMethod? {
        guard selectionIndex > 0 else { return nil }
        return InstallMethod.allCases[selectionIndex - 1]
    }

    private var nextMethod: InstallMethod? {
        guard selectionIndex < InstallMethod.allCases.count - 1 else { return nil }
        return InstallMethod.allCases[selectionIndex + 1]
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(InstallMethod.allCases) { method in
                InstallMethodView(
                    method: method,
                    description: method.description(for: guestType),
                    isSelected: selection == method
                )
                .onTapGesture {
                    selection = method
                }
            }
        }
        .accessibilityRepresentation {
            Picker(selection: $selection) {
                ForEach(InstallMethod.allCases) { method in
                    Text(method.description(for: guestType))
                        .tag(method)
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
                    if direction == .down {
                        guard let nextMethod else { return }
                        selection = nextMethod
                    } else if direction == .up {
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

struct InstallMethodView: View {

    let method: InstallMethod
    let description: String
    let isSelected: Bool

    var lineWidth: CGFloat { isSelected ? 2 : 1 }

    var body: some View {
        HStack {
            Image(systemName: method.imageName)

            Text(description)
        }
        .foregroundColor(isSelected ? .accentColor : .secondary)
        .padding()
        .multilineTextAlignment(.center)
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
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
struct InstallMethodPicker_Previews: PreviewProvider {
    static var previews: some View {
        InstallMethodPicker(guestType: .mac, selection: .constant(.remoteOptions))
    }
}
#endif
