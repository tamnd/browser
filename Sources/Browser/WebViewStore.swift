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
    private var accessOrder: [UUID] = []
    private var dataStores: [UUID: WKWebsiteDataStore] = [:]
    private var ruleList: WKContentRuleList?
    private var downloadIDs: [ObjectIdentifier: UUID] = [:]
    private var downloadObservations: [UUID: NSKeyValueObservation] = [:]
    private let userContentController = WKUserContentController()

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func webView(for tabID: UUID) -> WKWebView {
        if let view = views[tabID] {
            touch(tabID)
            return view
        }
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.websiteDataStore = dataStore(for: tabID)
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
        touch(tabID)
        observe(view, tabID: tabID)
        evictIfNeeded()
        if let url = model?.tab(tabID)?.url {
            view.load(URLRequest(url: url))
        }
        return view
    }

    // One persistent data store per workspace container, so workspaces
    // keep separate cookies and storage.
    private func dataStore(for tabID: UUID) -> WKWebsiteDataStore {
        guard let model,
              let ws = model.workspaces.first(where: { $0.tab(tabID) != nil }) else { return .default() }
        if let store = dataStores[ws.containerID] { return store }
        let store = WKWebsiteDataStore(forIdentifier: ws.containerID)
        dataStores[ws.containerID] = store
        return store
    }

    private func touch(_ tabID: UUID) {
        accessOrder.removeAll { $0 == tabID }
        accessOrder.append(tabID)
    }

    // Keep at most tabs.maxLiveWebviews alive. The least recently used
    // background webview is dropped; its tab reloads when shown again.
    private func evictIfNeeded() {
        guard let model else { return }
        let cap = model.config.tabs.maxLiveWebviews
        guard views.count > cap else { return }
        let visible = Set(model.activeWorkspace.paneTabIDs)
        for candidate in accessOrder where !visible.contains(candidate) {
            discard(tabID: candidate)
            if views.count <= cap { break }
        }
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
        accessOrder.removeAll { $0 == tabID }
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
        persistZoom(view)
    }

    func zoomReset() {
        guard let view = focusedWebView else { return }
        view.pageZoom = 1.0
        persistZoom(view)
    }

    private func persistZoom(_ view: WKWebView) {
        guard let host = view.url?.host else { return }
        model?.store?.setZoom(view.pageZoom, host: host)
    }

    // MARK: Find in page

    func find(_ text: String, forward: Bool, completion: @escaping (Bool) -> Void) {
        guard let view = focusedWebView, !text.isEmpty else {
            completion(false)
            return
        }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = false
        config.wraps = true
        view.find(text, configuration: config) { result in
            completion(result.matchFound)
        }
    }

    func clearSelection() {
        focusedWebView?.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
    }

    // MARK: Content rules and user styles

    func apply(ruleList newList: WKContentRuleList?) {
        if let ruleList {
            userContentController.remove(ruleList)
        }
        ruleList = newList
        if let newList {
            userContentController.add(newList)
        }
    }

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
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tabID = tabIDs[ObjectIdentifier(webView)] else { return }
        model?.updateTab(tabID) { $0.isLoading = false }
        guard let url = webView.url, url.scheme == "http" || url.scheme == "https" else { return }
        model?.store?.recordVisit(url: url.absoluteString, title: webView.title ?? "")
        model?.favicons.fetchIfNeeded(for: url)
        if let host = url.host {
            let saved = model?.store?.zoom(forHost: host) ?? 1.0
            if abs(webView.pageZoom - saved) > 0.001 {
                webView.pageZoom = saved
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(webView, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(webView, error: error)
    }

    private func handleLoadError(_ webView: WKWebView, error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        // WebKit reports "frame load interrupted" (102) when a navigation
        // turns into a download; that is not an error worth a page.
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        if let tabID = tabIDs[ObjectIdentifier(webView)] {
            model?.updateTab(tabID) { $0.isLoading = false }
        }
        let failed = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? webView.url?.absoluteString ?? ""
        webView.loadHTMLString(ErrorPage.html(message: nsError.localizedDescription, url: failed), baseURL: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        register(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        register(download)
    }

    private func register(_ download: WKDownload) {
        download.delegate = self
        let id = UUID()
        downloadIDs[ObjectIdentifier(download)] = id
        model?.downloadStarted(id: id)
        downloadObservations[id] = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            DispatchQueue.main.async {
                self?.model?.downloadProgress(id: id, fraction: fraction)
            }
        }
    }
}

extension WebViewStore: WKDownloadDelegate {
    nonisolated static func availableURL(for filename: String, in dir: URL) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = dir.appendingPathComponent(filename)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = dir.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = model?.config.downloads.resolvedURL
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = Self.availableURL(for: suggestedFilename, in: dir)
        if let id = downloadIDs[ObjectIdentifier(download)] {
            model?.downloadNamed(id: id, filename: target.lastPathComponent)
        }
        completionHandler(target)
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(download, error: nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(download, error: error)
    }

    private func finish(_ download: WKDownload, error: Error?) {
        guard let id = downloadIDs.removeValue(forKey: ObjectIdentifier(download)) else { return }
        downloadObservations.removeValue(forKey: id)?.invalidate()
        model?.downloadFinished(id: id, error: error?.localizedDescription)
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
