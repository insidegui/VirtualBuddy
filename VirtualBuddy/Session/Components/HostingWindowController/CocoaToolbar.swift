//
//  CocoaToolbar.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 13/05/22.
//

import SwiftUI

extension View {
    
    func cocoaToolbar<ToolbarContent>(style: NSWindow.ToolbarStyle = .unified, @ViewBuilder _ content: @escaping () -> ToolbarContent) -> some View where ToolbarContent: View {
        modifier(CocoaToolbar(style: style, content))
    }
    
}

fileprivate struct CocoaToolbarFullScreenReavealedKey: EnvironmentKey {
    static var defaultValue: Bool = false
}

extension EnvironmentValues {
    
    var cocoaToolbarFullScreenRevealed: Bool {
        get { self[CocoaToolbarFullScreenReavealedKey.self] }
        set { self[CocoaToolbarFullScreenReavealedKey.self] = newValue }
    }
    
}

fileprivate struct CocoaToolbar<ToolbarContent>: ViewModifier where ToolbarContent: View {
    
    let style: NSWindow.ToolbarStyle
    let contentBuilder: () -> ToolbarContent
    
    init(style: NSWindow.ToolbarStyle, @ViewBuilder _ content: @escaping () -> ToolbarContent) {
        self.style = style
        self.contentBuilder = content
    }
    
    @Environment(\.cocoaWindow) private var cocoaWindow
    @Environment(\.cocoaToolbarFullScreenRevealed) private var toolbarRevealed
    @State private var showFullScreenToolbar = false

    @State private var toolbarController: CocoaToolbarController<ToolbarContent>?
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing, content: {
                if toolbarRevealed {
                    fullScreenToolbar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            })
            .onAppear {
                guard toolbarController == nil else { return }
                guard let cocoaWindow = cocoaWindow else { return }
                
                toolbarController = CocoaToolbarController(window: cocoaWindow, toolbarStyle: style) {
                    contentBuilder()
                }
            }
            .onChange(of: toolbarRevealed) { newValue in
                withAnimation(.easeInOut) {
                    showFullScreenToolbar = newValue
                }
            }
    }
    
    @ViewBuilder
    private var fullScreenToolbar: some View {
        contentBuilder()
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .foregroundStyle(Material.thin)
            }
            .padding()
    }
    
}

fileprivate extension NSToolbarItem.Identifier {
    static let cocoaToolbarModifierDefault = NSToolbarItem.Identifier(rawValue: "codes.rambo.CocoaToolbarModifier.Default")
}

fileprivate final class CocoaToolbarController<Content>: NSObject, NSToolbarDelegate where Content: View {
    
    weak var window: NSWindow?
    let desiredStyle: NSWindow.ToolbarStyle
    let toolbarBuilder: () -> Content

    init(window: NSWindow, toolbarStyle: NSWindow.ToolbarStyle, @ViewBuilder _ content: @escaping () -> Content) {
        self.window = window
        self.desiredStyle = toolbarStyle
        self.toolbarBuilder = content
        
        super.init()
        
        setup(in: window)
    }
    
    private lazy var toolbar: NSToolbar = {
        let b = NSToolbar(identifier: .init("CocoaToolbarModifier-\(UUID())"))
        b.delegate = self
        b.displayMode = .iconOnly
        b.allowsUserCustomization = false
        b.showsBaselineSeparator = false
        return b
    }()
    
    private func setup(in window: NSWindow) {
        window.toolbar = toolbar
        window.toolbarStyle = desiredStyle
    }
    
    private let identifiers: [NSToolbarItem.Identifier] = [
        .cocoaToolbarModifierDefault
    ]
    
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .cocoaToolbarModifierDefault:
            return HostingToolbarItem(identifier: itemIdentifier, content: toolbarBuilder)
        default:
            return nil
        }
    }
    
}

fileprivate final class HostingToolbarItem<Content>: NSToolbarItem where Content: View {
    
    let contentBuilder: () -> Content
    
    init(identifier: NSToolbarItem.Identifier, @ViewBuilder content: @escaping () -> Content) {
        self.contentBuilder = content
        
        super.init(itemIdentifier: identifier)
        
        isBordered = false
        
        view = NSHostingView(rootView: contentBuilder())
    }
    
    override var allowsDuplicatesInToolbar: Bool { false }
    
}
