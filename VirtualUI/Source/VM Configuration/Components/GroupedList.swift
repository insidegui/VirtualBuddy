//
//  GroupedList.swift
//  VirtualUI
//
//  Created by Guilherme Rambo on 19/07/22.
//

import SwiftUI

struct GroupedList<Content: View, HeaderAccessory: View, FooterAccessory: View, EmptyOverlay: View, AddButton: View, RemoveButton: View>: View {
    
    var content: () -> Content
    var headerAccessory: () -> HeaderAccessory
    var footerAccessory: () -> FooterAccessory
    var emptyOverlay: () -> EmptyOverlay
    var addButton: (Label<Text, Image>) -> AddButton?
    var removeButton: (Label<Text, Image>) -> RemoveButton?
    
    init(@ViewBuilder _ content: @escaping () -> Content,
         headerAccessory: @escaping () -> HeaderAccessory,
         footerAccessory: @escaping () -> FooterAccessory,
         emptyOverlay: @escaping () -> EmptyOverlay,
         addButton: @escaping (Label<Text, Image>) -> AddButton? = { _ in nil },
         removeButton: @escaping (Label<Text, Image>) -> RemoveButton? = { _ in nil })
    {
        self.content = content
        self.headerAccessory = headerAccessory
        self.footerAccessory = footerAccessory
        self.emptyOverlay = emptyOverlay
        self.addButton = addButton
        self.removeButton = removeButton
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            content()
            .listStyle(.plain)
            .frame(minHeight: 140)
            .overlay { emptyOverlayContents }
            .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0, content: {
                listButtons
            })
            .materialBackground(.contentBackground, blendMode: .withinWindow, state: .active, in: listShape)
            .controlGroup(cornerRadius: listRadius, level: .secondary)
        }
    }
    
    @ViewBuilder
    private var emptyOverlayContents: some View {
        VStack {
            emptyOverlay()
        }
        .buttonStyle(.link)
        .frame(maxWidth: .infinity)
        .controlSize(.small)
    }

    private var listRadius: CGFloat { 8 }

    private var listShape: some InsettableShape {
        RoundedRectangle(cornerRadius: listRadius, style: .continuous)
    }
    
    @State private var showTip = false
    
    @ViewBuilder
    private var header: some View {
        headerAccessory()
            .padding(.horizontal, 2)
    }
    
    private let addLabel = Label("Add", systemImage: "plus")
    private let removeLabel = Label("Remove", systemImage: "minus")
    
    @ViewBuilder
    private var listButtons: some View {
        if addButton(addLabel) != nil || removeButton(removeLabel) != nil || FooterAccessory.self != EmptyView.self {
            HStack {
                Group {
                    if let addButton = addButton(addLabel) {
                        addButton
                    }
                    
                    if let removeButton = removeButton(removeLabel) {
                        removeButton
                    }
                }
                .labelStyle(.iconOnly)
                
                footerAccessory()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Material.thick, in: Rectangle())
            .overlay(alignment: .top) {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(.black.opacity(0.5))
            }
        }
    }
    
}

extension GroupedList where HeaderAccessory == EmptyView, FooterAccessory == EmptyView, EmptyOverlay == EmptyView, AddButton == EmptyView, RemoveButton == EmptyView {
    init(@ViewBuilder _ content: @escaping () -> Content)
    {
        self.content = content
        self.headerAccessory = { EmptyView() }
        self.footerAccessory = { EmptyView() }
        self.emptyOverlay = { EmptyView() }
        self.addButton = { _ in nil }
        self.removeButton = { _ in nil }
    }
}

extension GroupedList where FooterAccessory == EmptyView, EmptyOverlay == EmptyView, AddButton == EmptyView, RemoveButton == EmptyView {
    init(@ViewBuilder _ content: @escaping () -> Content, headerAccessory: @escaping () -> HeaderAccessory)
    {
        self.content = content
        self.headerAccessory = headerAccessory
        self.footerAccessory = { EmptyView() }
        self.emptyOverlay = { EmptyView() }
        self.addButton = { _ in nil }
        self.removeButton = { _ in nil }
    }
}

extension GroupedList where HeaderAccessory == EmptyView, FooterAccessory == EmptyView {
    init(@ViewBuilder _ content: @escaping () -> Content,
         emptyOverlay: @escaping () -> EmptyOverlay,
         addButton: @escaping (Label<Text, Image>) -> AddButton? = { _ in nil },
         removeButton: @escaping (Label<Text, Image>) -> RemoveButton? = { _ in nil })
    {
        self.content = content
        self.headerAccessory = { EmptyView() }
        self.footerAccessory = { EmptyView() }
        self.emptyOverlay = emptyOverlay
        self.addButton = addButton
        self.removeButton = removeButton
    }
}
