//
//  AuthenticatingWebView.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/06/22.
//

import SwiftUI
import WebKit

struct AuthenticatingWebView: NSViewControllerRepresentable {

    typealias NSViewControllerType = AuthenticatingWebViewController

    let url: URL
    let onCookiesChanged: ([HTTPCookie]) -> Void

    init(url: URL, onCookiesChanged: @escaping ([HTTPCookie]) -> Void) {
        self.url = url
        self.onCookiesChanged = onCookiesChanged
    }

    func makeNSViewController(context: Context) -> AuthenticatingWebViewController {
        AuthenticatingWebViewController(url: url) { 🍪 in
            DispatchQueue.main.async {
                self.onCookiesChanged(🍪)
            }
        }
    }

    func updateNSViewController(_ nsViewController: AuthenticatingWebViewController, context: Context) {

    }

}

final class AuthenticatingWebViewController: NSViewController, WKUIDelegate, WKNavigationDelegate, WKHTTPCookieStoreObserver {

    var url: URL
    var cookiesChangedCallback: ([HTTPCookie]) -> Void

    init(url: URL, cookiesChangedCallback: @escaping ([HTTPCookie]) -> Void) {
        self.url = url
        self.cookiesChangedCallback = cookiesChangedCallback

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private var requestSent = false

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        let v = WKWebView(frame: .zero, configuration: config)

        v.uiDelegate = self
        v.navigationDelegate = self

        config.websiteDataStore.httpCookieStore.add(self)

        return v
    }()

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard !requestSent else { return }
        requestSent = true

        webView.load(URLRequest(url: url))
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        print("Cookies changed")

        cookieStore.getAllCookies { [weak self] cookies in
            self?.cookiesChangedCallback(cookies)
        }
    }
}
