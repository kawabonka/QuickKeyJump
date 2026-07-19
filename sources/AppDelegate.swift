import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private let folderManager = RecentFolderManager()
    private let quickJumpPanel = QuickJumpPanel.shared
    private var statusItem: NSStatusItem?
    private var hasShownPermissionAlert = false
    private var previousFrontmostApp: NSRunningApplication?
    private var settingsWindow: NSWindow?

    // MARK: 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBarItem()
        registerAllShortcuts()
        folderManager.loadRecentFolders(maxResults: 5)
        LaunchManager.syncWithPreference()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAccessibilityPermission()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    // MARK: 快捷键注册（KeyboardShortcuts 自动处理全局热键）

    private func registerAllShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .quickJump) { [weak self] in
            self?.executeQuickJump()
        }
        KeyboardShortcuts.onKeyDown(for: .defaultBrowser) { [weak self] in
            self?.executeDefaultBrowser()
        }
        for action in ActionType.allCases where action.windowAction != nil {
            KeyboardShortcuts.onKeyDown(for: action.name) { [weak self] in
                self?.executeWindowAction(action)
            }
        }
    }

    // MARK: 菜单栏 (Q⌘ 图标)

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = createMenuBarIcon()

        let menu = NSMenu(title: "QuickKeyJump")
        let prefsItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettingsMenuAction), keyEquivalent: ",")
        prefsItem.target = self; menu.addItem(prefsItem)
        menu.addItem(NSMenuItem.separator())

        let autoItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = LaunchManager.isEnabled ? .on : .off
        menu.addItem(autoItem)
        menu.addItem(NSMenuItem.separator())

        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        menu.addItem(NSMenuItem(title: "QuickKeyJump v\(ver)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 QuickKeyJump", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self; menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    private func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 35, height: 20)
        let img = NSImage(size: size)
        img.isTemplate = true
        img.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        NSAttributedString(string: "Q\u{2318}", attributes: attrs).draw(at: NSPoint(x: 2, y: 2))
        img.unlockFocus()
        return img
    }

    // MARK: 快速跳转

    private func executeQuickJump() {
        if quickJumpPanel.isVisible { quickJumpPanel.close(); return }
        previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        folderManager.loadRecentFolders(maxResults: 5)
        quickJumpPanel.show(
            folderManager: folderManager,
            onSelect: { [weak self] f in self?.quickJumpPanel.close(); self?.handleNavigation(to: f) },
            onCancel: { [weak self] in self?.quickJumpPanel.close() }
        )
    }

    private func handleNavigation(to folder: RecentFolder) {
        let prev = previousFrontmostApp; previousFrontmostApp = nil
        guard let app = prev else { return }
        app.activate(options: .activateAllWindows)
        if app.bundleIdentifier == "com.apple.finder" {
            FinderWindowNavigator.shared.navigateTo(folder.path); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.raiseDialogWindow(in: app)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.navigateDialog(to: folder.path)
            }
        }
    }

    private func navigateDialog(to path: String) {
        guard DialogNavigator.checkPermission() else {
            DialogNavigator.requestPermission(); showPermissionAlert(for: .appleEvents); return
        }
        if !DialogNavigator.navigateTo(path: path) { print("[QKJ] nav fail: \(path)") }
    }

    private func raiseDialogWindow(in app: NSRunningApplication) {
        let ae = AXUIElementCreateApplication(app.processIdentifier)
        var wv: AnyObject?
        guard AXUIElementCopyAttributeValue(ae, kAXWindowsAttribute as CFString, &wv) == .success,
              let ws = wv as? [AXUIElement] else { return }
        for w in ws {
            var sv: AnyObject?
            if AXUIElementCopyAttributeValue(w, "AXSheets" as CFString, &sv) == .success,
               let s = sv as? [AXUIElement], !s.isEmpty { AXUIElementPerformAction(w, kAXRaiseAction as CFString); return }
            var rv: AnyObject?
            if AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &rv) == .success,
               (rv as? String) == "AXDialog" { AXUIElementPerformAction(w, kAXRaiseAction as CFString); return }
            var mv: AnyObject?
            if AXUIElementCopyAttributeValue(w, kAXModalAttribute as CFString, &mv) == .success,
               (mv as? Bool) == true { AXUIElementPerformAction(w, kAXRaiseAction as CFString); return }
        }
    }

    // MARK: 默认浏览器

    private func executeDefaultBrowser() {
        if let u = URL(string: "https://") { NSWorkspace.shared.open(u) }
    }

    // MARK: 窗口管理（直接下发到 WindowManager）

    private func executeWindowAction(_ type: ActionType) {
        guard let wa = type.windowAction else { return }
        WindowManager.shared.execute(wa)
    }

    // MARK: 设置窗口

    @objc private func openSettingsMenuAction() { openSettings() }

    func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let sv = SettingsView()
        let hv = NSHostingView(rootView: sv)
        hv.frame = NSRect(x: 0, y: 0, width: 480, height: 560)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "QuickKeyJump 偏好设置"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 360, height: 400)
        w.contentView = hv
        w.center()
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            self?.settingsWindow = nil
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 菜单

    @objc private func toggleAutoStart(_ sender: NSMenuItem) {
        if LaunchManager.isEnabled { LaunchManager.disable(); sender.state = .off }
        else { LaunchManager.enable(); sender.state = .on }
    }

    @objc private func quitApplication() { NSApplication.shared.terminate(self) }

    // MARK: 权限

    private enum PermissionType { case accessibility, appleEvents }

    private func checkAccessibilityPermission(showAlert: Bool = true) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: showAlert]
        if !AXIsProcessTrustedWithOptions(opts as CFDictionary), !hasShownPermissionAlert {
            hasShownPermissionAlert = true; showPermissionAlert(for: .accessibility)
        }
    }

    private func showPermissionAlert(for type: PermissionType) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "需要授权才能使用 QuickKeyJump"
        a.informativeText = type == .accessibility
            ? "QuickKeyJump 需要「辅助功能」权限。"
            : "QuickKeyJump 需要控制 Finder 的权限。"
        a.addButton(withTitle: "打开设置")
        a.addButton(withTitle: "稍后")
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
