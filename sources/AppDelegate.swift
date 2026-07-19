import Cocoa
import Carbon
import ApplicationServices
import SwiftUI

// MARK: - 全局快捷键标识符 "QKJP"
private let kHotKeySignature: FourCharCode = (81 << 24) | (75 << 16) | (74 << 8) | 80

/// QuickKeyJump 应用委托 — 协调全局快捷键、快速操作执行、菜单栏和设置窗口
class AppDelegate: NSObject, NSApplicationDelegate {

    private let folderManager = RecentFolderManager()
    private let quickJumpPanel = QuickJumpPanel.shared
    private let settingsManager = SettingsManager.shared

    private var statusItem: NSStatusItem?
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [ActionType: EventHotKeyRef] = [:]

    private var hasShownPermissionAlert = false
    private var previousFrontmostApp: NSRunningApplication?
    private var settingsWindow: NSWindow?

    // MARK: 应用生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBarItem()
        registerAllHotKeys()
        folderManager.loadRecentFolders(maxResults: 5)
        LaunchManager.syncWithPreference()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAccessibilityPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterAllHotKeys()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    // MARK: 菜单栏

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        if let icon = loadMenuBarIcon() {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = false
            button.image = icon
        } else {
            button.image = NSImage(systemSymbolName: "command.square.fill",
                                    accessibilityDescription: "QuickKeyJump")
        }

        let menu = NSMenu(title: "QuickKeyJump")

        let prefsItem = NSMenuItem(
            title: NSLocalizedString("偏好设置...", comment: ""),
            action: #selector(openSettingsMenuAction),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(NSMenuItem.separator())

        let autoStartItem = NSMenuItem(
            title: NSLocalizedString("开机自动启动", comment: ""),
            action: #selector(toggleAutoStart),
            keyEquivalent: ""
        )
        autoStartItem.target = self
        autoStartItem.state = LaunchManager.isEnabled ? .on : .off
        menu.addItem(autoStartItem)
        menu.addItem(NSMenuItem.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let versionItem = NSMenuItem(
            title: NSLocalizedString("QuickKeyJump v\(version)", comment: ""),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: NSLocalizedString("退出 QuickKeyJump", comment: ""),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func loadMenuBarIcon() -> NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            return NSImage(contentsOfFile: path)
        }
        let sourcesPath = Bundle.main.bundlePath + "/../../../sources/AppIcon.icns"
        if FileManager.default.fileExists(atPath: sourcesPath) {
            return NSImage(contentsOfFile: sourcesPath)
        }
        let cwdPath = FileManager.default.currentDirectoryPath + "/AppIcon.icns"
        if FileManager.default.fileExists(atPath: cwdPath) {
            return NSImage(contentsOfFile: cwdPath)
        }
        return nil
    }

    // MARK: 全局热键管理

    func registerAllHotKeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        if eventHandlerRef == nil {
            let installStatus = InstallEventHandler(
                GetEventDispatcherTarget(),
                { (_, eventRef, userData) -> OSStatus in
                    guard let userData = userData else { return noErr }
                    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    return appDelegate.handleHotKeyEvent(eventRef)
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
            guard installStatus == noErr else {
                print("[QuickKeyJump] 安装热键事件处理器失败: \(installStatus)")
                return
            }
        }
        for action in ActionType.allCases {
            registerHotKey(for: action)
        }
    }

    private func registerHotKey(for action: ActionType) {
        let shortcut = settingsManager.shortcut(for: action)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            UInt32(shortcut.modifiers),
            EventHotKeyID(signature: kHotKeySignature, id: action.hotKeyID),
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[action] = ref
            print("[QuickKeyJump] 已注册: \(action.displayName) → \(shortcut.displayString)")
        } else {
            print("[QuickKeyJump] 注册失败: \(action.displayName) \(status)")
        }
    }

    func reRegisterHotKey(for action: ActionType) {
        if let ref = hotKeyRefs[action] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: action)
        }
        registerHotKey(for: action)
    }

    func reRegisterAllHotKeys() {
        for (_, ref) in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        for action in ActionType.allCases { registerHotKey(for: action) }
    }

    private func unregisterAllHotKeys() {
        for (_, ref) in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
    }

    private func handleHotKeyEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef = eventRef else { return noErr }
        var hotKeyID = EventHotKeyID()
        let result = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard result == noErr else { return result }
        guard hotKeyID.signature == kHotKeySignature else { return noErr }

        let action = ActionType.allCases.first { $0.hotKeyID == hotKeyID.id }
        guard let action = action else { return noErr }

        DispatchQueue.main.async { [weak self] in
            self?.executeAction(action)
        }
        return noErr
    }

    // MARK: 快捷操作执行

    private func executeAction(_ action: ActionType) {
        switch action {
        case .quickJump:      executeQuickJump()
        case .defaultBrowser: executeDefaultBrowser()
        case .screenshot:     executeScreenshot()
        }
    }

    // MARK: 快速跳转

    private func executeQuickJump() {
        if quickJumpPanel.isVisible {
            quickJumpPanel.close()
            return
        }
        previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        folderManager.loadRecentFolders(maxResults: 5)
        quickJumpPanel.show(
            folderManager: folderManager,
            onSelect: { [weak self] folder in
                self?.quickJumpPanel.close()
                self?.handleNavigation(to: folder)
            },
            onCancel: { [weak self] in
                self?.quickJumpPanel.close()
            }
        )
    }

    private func handleNavigation(to folder: RecentFolder) {
        let prevApp = previousFrontmostApp
        previousFrontmostApp = nil
        guard let app = prevApp else { return }
        app.activate(options: .activateAllWindows)
        if app.bundleIdentifier == "com.apple.finder" {
            FinderWindowNavigator.shared.navigateTo(folder.path)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.raiseDialogWindow(in: app)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.navigateDialog(to: folder.path)
            }
        }
    }

    private func navigateDialog(to path: String) {
        guard DialogNavigator.checkPermission() else {
            DialogNavigator.requestPermission()
            showPermissionAlert(for: .appleEvents)
            return
        }
        if !DialogNavigator.navigateTo(path: path) {
            print("[QuickKeyJump] 导航失败: \(path)")
        }
    }

    private func raiseDialogWindow(in app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return }
        for window in windows {
            var sheetsValue: AnyObject?
            if AXUIElementCopyAttributeValue(window, "AXSheets" as CFString, &sheetsValue) == .success,
               let sheets = sheetsValue as? [AXUIElement], !sheets.isEmpty {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return
            }
            var subroleValue: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
               (subroleValue as? String) == "AXDialog" {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return
            }
            var modalValue: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXModalAttribute as CFString, &modalValue) == .success,
               (modalValue as? Bool) == true {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return
            }
        }
    }

    // MARK: 默认浏览器

    private func executeDefaultBrowser() {
        if let url = URL(string: "https://") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 截图

    private func executeScreenshot() {
        let process = Process()
        process.launchPath = "/usr/sbin/screencapture"
        process.arguments = ["-i", "-c", "-s"]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: 设置窗口

    @objc private func openSettingsMenuAction() {
        openSettings()
    }

    func openSettings() {
        if let existingWindow = settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(settings: settingsManager) { [weak self] in
            self?.reRegisterAllHotKeys()
        }
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 380)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickKeyJump 偏好设置"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 菜单操作

    @objc private func toggleAutoStart(_ sender: NSMenuItem) {
        if LaunchManager.isEnabled {
            LaunchManager.disable()
            sender.state = .off
        } else {
            LaunchManager.enable()
            sender.state = .on
        }
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(self)
    }

    // MARK: 权限检查

    private enum PermissionType {
        case accessibility
        case appleEvents
    }

    private func checkAccessibilityPermission(showAlert: Bool = false) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: showAlert]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !isTrusted && !hasShownPermissionAlert {
            hasShownPermissionAlert = true
            showPermissionAlert(for: .accessibility)
        }
    }

    private func showPermissionAlert(for type: PermissionType) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要授权才能使用 QuickKeyJump"
        alert.informativeText = type == .accessibility
            ? "QuickKeyJump 需要「辅助功能」权限来检测前台窗口和对话框。"
            : "QuickKeyJump 需要控制 Finder 的权限来自动导航。"
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
