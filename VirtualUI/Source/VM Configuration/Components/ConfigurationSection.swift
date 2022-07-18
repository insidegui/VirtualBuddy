//
//  ConfigurationSection.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 18/07/22.
//

import SwiftUI
import VirtualCore

struct ConfigurationSection<Header: View, Content: View>: View {

    @State private var isCollapsed = false

    var content: () -> Content
    var header: () -> Header

    init(@ViewBuilder _ content: @escaping () -> Content, @ViewBuilder header: @escaping () -> Header) {
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
    }

    @ViewBuilder
    private var styledHeader: some View {
        HStack {
            header()
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
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
                withAnimation(.default) {
                    isCollapsed.toggle()
                }
            }
    }

}
