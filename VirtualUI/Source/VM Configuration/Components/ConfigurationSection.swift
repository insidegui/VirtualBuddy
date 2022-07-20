//
//  ConfigurationSection.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct ConfigurationSection<Header: View, Content: View>: View {

    @Binding private var collapsedStateBinding: Bool
    @State private var isCollapsed: Bool

    var content: () -> Content
    var header: () -> Header
    var collapsingDisabled: Bool

    init(_ collapsed: Binding<Bool>? = nil, collapsingDisabled: Bool = false, @ViewBuilder _ content: @escaping () -> Content, @ViewBuilder header: @escaping () -> Header) {
        if collapsingDisabled {
            self._collapsedStateBinding = .constant(false)
            self._isCollapsed = .init(wrappedValue: false)
        } else {
            self._collapsedStateBinding = collapsed ?? .constant(true)
            self._isCollapsed = .init(wrappedValue: collapsed?.wrappedValue ?? true)
        }
        self.collapsingDisabled = collapsingDisabled
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            styledHeader

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                    .padding()
                    .transition(.opacity)
            }
        }
        .controlGroup()
        .onChange(of: collapsedStateBinding) { newValue in
            guard newValue != isCollapsed else { return }
            isCollapsed = newValue
        }
        .onChange(of: isCollapsed) { newValue in
            guard collapsedStateBinding != newValue else { return }
            collapsedStateBinding = newValue
        }
    }

    @ViewBuilder
    private var styledHeader: some View {
        HStack {
            header()
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if !collapsingDisabled {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
        }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Material.ultraThick, in: Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .frame(maxWidth: .infinity, maxHeight: 0.5)
                    .foregroundColor(.black.opacity(isCollapsed ? 0 : 0.5))
            }
            .onTapGesture {
                guard !collapsingDisabled else { return }
                
                withAnimation(.default) {
                    isCollapsed.toggle()
                }
            }
    }

}
