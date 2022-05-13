// WIP
//
////
////  FullScreenModifier.swift
////  CustomFullScreen
////
////  Created by Guilherme Rambo on 13/05/22.
////
//
//import SwiftUI
//import Combine
//
//extension View {
//
//    func fullScreen(presented: Binding<Bool>) -> some View {
//        modifier(FullScreenModifier(isInFullScreen: presented))
//    }
//
//}
//
//private struct FullScreenModifier: ViewModifier {
//
//    @Binding var isInFullScreen: Bool
//
//    @Environment(\.cocoaWindow) private var hostingWindow
//
//    @State private var revealToolbar = false
//
//    func body(content: Content) -> some View {
//        if let hostingViewController = hostingWindow?.contentViewController {
//            content
//                .onChange(of: isInFullScreen) { newValue in
//                    guard newValue != hostingViewController.isInFullScreen else { return }
//
//                    if newValue {
//                        let fs = FullScreenWindowController.present(hostingViewController)
//                        fs.titleBarRevealCallback = { reveal in
//                            revealToolbar = reveal
//                        }
//                    } else {
//                        FullScreenWindowController.dismiss(hostingViewController)
//                    }
//                }
//                .environment(\.cocoaToolbarFullScreenRevealed, revealToolbar)
//        } else {
//            AppKitSwiftUIContentWrapper(isInFullScreen: $isInFullScreen, content: {
//                content
//            })
//        }
//    }
//
//}
//
//private struct DismissFullScreenContentKey: EnvironmentKey {
//    static var defaultValue: () -> Void = { }
//}
//
//private extension EnvironmentValues {
//    var dismissFullScreenContent: () -> Void {
//        get { self[DismissFullScreenContentKey.self] }
//        set { self[DismissFullScreenContentKey.self] = newValue }
//    }
//}
//
//@MainActor
//private final class AppKitSwiftUIContentWrapper<Content>: NSViewControllerRepresentable where Content: View {
//
//    typealias NSViewControllerType = NSViewController
//
//    @Binding var isInFullScreen: Bool
//    let contentBuilder: () -> Content
//
//    init(isInFullScreen: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
//        self._isInFullScreen = isInFullScreen
//        self.contentBuilder = content
//    }
//
//    func makeNSViewController(context: Context) -> NSViewControllerType {
//        if let controller = context.coordinator.controller {
//            return controller
//        } else {
//            let rootView = contentBuilder().environment(\.dismissFullScreenContent, {
//                context.coordinator.dismissFullScreen()
//            })
//            let controller = NSHostingController(rootView: rootView)
//            context.coordinator.controller = controller
//            return controller
//        }
//    }
//
//    func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context) {
//        guard isInFullScreen != nsViewController.isInFullScreen else { return }
//
//        if isInFullScreen {
//            FullScreenWindowController.present(nsViewController)
//        } else {
//            context.coordinator.dismissFullScreen()
//        }
//    }
//
//    private lazy var coordinator = Coordinator(controller: nil)
//
//    func makeCoordinator() -> Coordinator {
//        coordinator
//    }
//
//    @MainActor
//    final class Coordinator {
//        var controller: NSViewControllerType?
//        init(controller: NSViewControllerType?) {
//            self.controller = controller
//        }
//
//        func dismissFullScreen() {
//            guard let controller = controller else {
//                return
//            }
//
//            FullScreenWindowController.dismiss(controller)
//        }
//    }
//
//}
