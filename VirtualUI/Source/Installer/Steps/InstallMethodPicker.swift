//
//  InstallMethodPicker.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import SwiftUI

enum InstallMethod: String, Identifiable, CaseIterable, CustomStringConvertible {
    var id: RawValue { rawValue }

    case localFile
    case remoteOptions
    case remoteManual

    var description: String {
        switch self {
            case .localFile:
                return "Open custom IPSW file from local storage"
            case .remoteOptions:
                return "Download macOS installer from a list of options"
            case .remoteManual:
                return "Download macOS installer from a custom URL"
        }
    }

    var imageName: String {
        switch self {
            case .localFile:
                return "externaldrive.fill.badge.plus"
            case .remoteOptions:
                return "network"
            case .remoteManual:
                return "questionmark.app.fill"
        }
    }
}

struct InstallMethodPicker: View {

    @Binding var selection: InstallMethod

    var body: some View {
        HStack(spacing: 16) {
            ForEach(InstallMethod.allCases) { method in
                InstallMethodView(
                    method: method,
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
                    Text(method.description)
                        .tag(method)
                }
            } label: { }
        }
    }

}

struct InstallMethodView: View {

    let method: InstallMethod
    let isSelected: Bool

    var body: some View {
        VStack {
            Image(systemName: method.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 50)

            Spacer()

            Text(method.description)
        }
        .foregroundColor(isSelected ? .accentColor : nil)
        .padding()
        .frame(width: 200, height: 140)
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)
        .font(.system(size: 13, weight: .medium))
        .background {
            shape
                .foregroundStyle(isSelected ? Material.ultraThick : Material.thin)
                .overlay(shape.stroke(borderColor, style: StrokeStyle(lineWidth: 2)))
        }
    }

    private var borderColor: Color {
        isSelected ? .accentColor : .secondary.opacity(0.5)
    }

    private var shape: some Shape {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

}
