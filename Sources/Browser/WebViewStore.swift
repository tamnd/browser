import AppKit
import Combine
import Foundation
import WebKit

// Owns every live WKWebView keyed by tab id.
// Webviews live outside SwiftUI so state changes never recreate them.
@MainActor
final class WebViewStore: NSObject {
    private weak var model: AppModel?
    private var views: [UUID: WKWebView] = [:]
    private var tabIDs: [ObjectIdentifier: UUID] = [:]
    private var cancellables: [UUID: Set<AnyCancellable>] = [:]
    private let userContentController = WKUserContentController()

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func webView(for tabID: UUID) -> WKWebView {
        if let view = views[tabID] { return view }
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        if #available(macOS 12.3, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsMagnification = true
        view.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) {
            view.isInspectable = true
        }
        views[tabID] = view
        tabIDs[ObjectIdentifier(view)] = tabID
        observe(view, tabID: tabID)
        if let url = model?.tab(tabID)?.url {
            view.load(URLRequest(url: url))
        }
        return view
    }

    private func observe(_ view: WKWebView, tabID: UUID) {
        var bag = Set<AnyCancellable>()
        view.publisher(for: \.title)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                guard let title, !title.isEmpty else { return }
                self?.model?.updateTab(tabID) { $0.title = title }
                if let url = view.url?.absoluteString {
                    self?.model?.store?.updateTitle(url: url, title: title)
                }
            }
            .store(in: &bag)
        view.publisher(for: \.url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                guard let url else { return }
                self?.model?.updateTab(tabID) { $0.url = url }
            }
            .store(in: &bag)
        view.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                self?.model?.updateTab(tabID) { $0.isLoading = loading }
            }
            .store(in: &bag)
        cancellables[tabID] = bag
    }

    func load(url: URL, in tabID: UUID) {
        webView(for: tabID).load(URLRequest(url: url))
    }

    func discard(tabID: UUID) {
        guard let view = views.removeValue(forKey: tabID) else { return }
        tabIDs.removeValue(forKey: ObjectIdentifier(view))
        cancellables.removeValue(forKey: tabID)
        view.stopLoading()
        view.removeFromSuperview()
    }

    private var focusedWebView: WKWebView? {
        guard let model else { return nil }
        let ws = model.activeWorkspace
        guard let id = ws.activeTabID else { return nil }
        return views[id]
    }

    func goBack() { focusedWebView?.goBack() }
    func goForward() { focusedWebView?.goForward() }
    func reload() { focusedWebView?.reload() }

    func zoom(by delta: Double) {
        guard let view = focusedWebView else { return }
        view.pageZoom = min(max(view.pageZoom + delta, 0.5), 3.0)
    }

    func zoomReset() { focusedWebView?.pageZoom = 1.0 }

    // Snippets are injected through the shared user content controller,
    // so one reload updates every webview's next navigation.
    func reloadUserStyles() {
        userContentController.removeAllUserScripts()
        for css in UserStyles.loadSnippets(from: Profile.snippetsURL) {
            userContentController.addUserScript(UserStyles.script(for: css))
        }
    }
}

extension WebViewStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tabID = tabIDs[ObjectIdentifier(webView)],
              let url = webView.url?.absoluteString else { return }
        let title = webView.title ?? ""
        model?.store?.recordVisit(url: url, title: title)
        model?.updateTab(tabID) { $0.isLoading = false }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

extension WebViewStore: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url,
           let model,
           let openerID = tabIDs[ObjectIdentifier(webView)] {
            let id = model.newTab(url: url, parentID: openerID)
            model.navigate(tabID: id, to: url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.url?.host ?? "Page"
        alert.informativeText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = webView.url?.host ?? "Page"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}
