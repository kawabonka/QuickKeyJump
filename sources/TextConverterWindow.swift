import Cocoa
import WebKit

/// Local conversion UI; clipboard access stays in the native application.
final class TextConverterWindow: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "TextConverter") else {
            let alert = NSAlert()
            alert.messageText = L("文本转换资源缺失，请重新构建应用。", "Converter resources are missing. Please rebuild the app.")
            alert.runModal()
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "clipboard")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L("文本转换粘贴", "Clipboard Converter")
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.center()
        self.window = window
        webView = view
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("setLanguage(\(AppLanguage.current == .zh ? "true" : "false"))")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: String], let action = body["action"] else { return }
        let pasteboard = NSPasteboard.general
        if action == "paste" {
            let payload = ["text": pasteboard.string(forType: .string) ?? "",
                           "html": pasteboard.string(forType: .html) ?? ""]
            if let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) {
                webView?.evaluateJavaScript("receiveClipboard(\(json))")
            }
        } else if action == "copy", let text = body["text"] {
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            if let html = body["html"], !html.isEmpty { item.setString(html, forType: .html) }
            pasteboard.clearContents()
            let success = pasteboard.writeObjects([item])
            webView?.evaluateJavaScript("copyFinished(\(success))")
        }
    }
}
