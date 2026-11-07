// Run with ApplicationMenu.swift and Localization.swift, passing index.html.
// Add --editing for interactive shortcut checks; keep that test window focused.
import Cocoa
import WebKit

@main
final class ClipboardConverterTests: NSObject, WKNavigationDelegate {
    private var window: NSWindow!
    private var view: WKWebView!
    private var savedClipboard: [[NSPasteboard.PasteboardType: Data]] = []
    private var failures = 0
    private var checks = 0
    private let editing: [(String, String, String)] = [
        ("a", "", "$('input').selectionStart===0 && $('input').selectionEnd===5"),
        ("c", "", "$('input').value==='hello'"),
        ("x", "", "$('input').value===''") ,
        ("v", "", "$('input').value==='hello'"),
        ("z", "", "$('input').value===''") ,
        ("z", "shift", "$('input').value==='hello'")
    ]
    static func main() {
        let test = ClipboardConverterTests()
        test.start()
        NSApp.run()
    }
    private func start() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        savedClipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var result: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { result[type] = item.data(forType: type) }
            return result
        }
        ApplicationMenu.install()
        view = WKWebView()
        view.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { self.finish(timeout: true) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = #"""
        (() => {
          const checks=[];
          function run(html){$('input').value=html;$('source').value='html';$('target').value='markdown';convert();return $('output').value;}
          const md=run('<p>区域业绩：</p><p><span>- </span><span>欧洲区：内容</span></p><p>- 美洲区：内容</p>');
          checks.push(md.includes('\n\n- 欧洲区：内容'));
          checks.push(md.includes('\n\n- 美洲区：内容'));
          checks.push(!md.includes('\\-'));
          checks.push(marked.parse(md).includes('<li>'));
          checks.push(run('<ul><li>正常列表</li></ul>').includes('-'));
          checks.push(run('<pre><code>- code\n</code></pre>').includes('- code'));
          checks.push(run('<p>文字 *星号*</p>').includes('\\*星号\\*'));
          checks.push(run('<p><strong>加粗</strong></p>')==='**加粗**');
          const nbsp=run('<p>-&nbsp;项目</p>'); checks.push(/^-[ \u00a0]项目$/.test(nbsp));
          // Office clipboard fragments may omit the final paragraph wrapper.
          const wrappers = [
            text => '<p>'+text+'</p>', text => '<div>'+text+'</div>',
            text => '<span>'+text+'</span><br>', text => text+'<br>',
            text => '<p><span>-</span><span> '+text.slice(2)+'</span></p>',
            text => '<div><span>'+text+'</span></div>',
            text => '<p>'+text.replace(' ', '&nbsp;')+'</p>',
            text => '<p>'+text.replace(' ', '\t')+'</p>'
          ];
          for (const count of [1,2,3,5]) {
            for (const wrap of wrappers) {
              for (const end of ['wrapped','span','bare']) {
                const lines=Array.from({length:count}, (_,i)=>'- 项目'+i);
                let html='<p>说明：</p>'+lines.map((line,i)=>i===count-1 && end!=='wrapped' ? (end==='span'?'<span>'+line+'</span>':line) : wrap(line)).join('');
                const out=run(html);
                const pass=!out.includes('\\-') && lines.every((_,i)=>out.includes('项目'+i));
                if(!pass) console.log('FAILED',count,end,html,out);
                checks.push(pass);
              }
            }
          }
          const mixed=run('<p>说明</p><p>- 第一项</p><span>- 最后一项</span>');
          checks.push(!mixed.includes('\\-'));
          checks.push(run('<pre><code>\\- literal\n- code</code></pre>').includes('\\- literal'));
          checks.push(run('<p><code>\\- inline</code></p>').includes('`\\- inline`'));
          checks.push(run('<p>原文\\- 保留</p>').includes('\\\\-'));
          checks.push(run('<p>文字<span>- 内容</span></p>')==='文字- 内容');
          checks.push(run('<blockquote><p>- 引用列表</p></blockquote>').startsWith('> - '));
          checks.push(run('<ul><li>父项<ul><li>子项</li></ul></li></ul>').includes('子项'));
          $('source').value='plain';$('input').value='hello';$('input').focus();$('input').setSelectionRange(5,5);
          return checks;
        })()
        """#
        view.evaluateJavaScript(script) { result, error in
            guard let results = result as? [Bool], error == nil else { print("JS error: \(String(describing: error))"); self.finish(timeout: true); return }
            self.checks += results.count
            self.failures += results.filter { !$0 }.count
            print("Markdown regression checks: \(results.count), failed indices: \(results.indices.filter { !results[$0] })")
            if !CommandLine.arguments.contains("--editing") { self.finish(); return }
            self.view.evaluateJavaScript("$('input').focus()") { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.edit(0) }
            }
        }
    }
    private func edit(_ index: Int) {
        guard index < editing.count else { finish(); return }
        let step = editing[index]
        let modifiers: NSEvent.ModifierFlags = step.1 == "shift" ? [.command, .shift] : [.command]
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    characters: step.0, charactersIgnoringModifiers: step.0,
                                    isARepeat: false, keyCode: 0)!
        let handled = NSApp.mainMenu!.performKeyEquivalent(with: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.view.evaluateJavaScript(step.2) { result, error in
                let passed = handled && (result as? Bool) == true && error == nil
                self.checks += 1
                if !passed { self.failures += 1 }
                print("Command-\(step.1)\(step.0): \(passed), handled=\(handled), result=\(String(describing: result))")
                self.edit(index + 1)
            }
        }
    }
    private func finish(timeout: Bool = false) {
        let board = NSPasteboard.general
        board.clearContents()
        let items = savedClipboard.map { data -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, value) in data { item.setData(value, forType: type) }
            return item
        }
        if !items.isEmpty { board.writeObjects(items) }
        print("\(checks) checks, \(failures) failures\(timeout ? " (timeout/error)" : "")")
        exit(failures == 0 && !timeout ? 0 : 1)
    }
}
