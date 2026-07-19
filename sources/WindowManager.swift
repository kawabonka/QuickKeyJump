import Cocoa

enum WindowAction: String, CaseIterable {
    case leftHalf, rightHalf, maximize, almostMaximize, nextDisplay, reasonableSize
    var displayName: String {
        switch self {
        case .leftHalf: "左半屏"; case .rightHalf: "右半屏"; case .maximize: "最大化"
        case .almostMaximize: "几乎最大化"; case .nextDisplay: "下一显示器"; case .reasonableSize: "合适大小"
        }
    }
    var icon: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.inset.filled"; case .rightHalf: "rectangle.righthalf.inset.filled"
        case .maximize: "rectangle.inset.filled"; case .almostMaximize: "rectangle.center.inset.filled"
        case .nextDisplay: "rectangle.2.swap"; case .reasonableSize: "rectangle.portrait.center.inset.filled"
        }
    }
    var shortcut: String { String(Self.allCases.firstIndex(of: self)! + 1) }
}

final class WindowManager {
    static let shared = WindowManager()
    private let gapSize: CGFloat = 8

    private init() {}

    func execute(_ action: WindowAction) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            print("[QKJ] WM: no frontmost application"); return
        }
        guard let win = findWindow(for: frontApp) else {
            print("[QKJ] WM: no window for \(frontApp.localizedName ?? "?")"); return
        }
        guard let currentFrame = getFrame(win),
              let currentScreen = screenContaining(currentFrame) else {
            print("[QKJ] WM: cannot get frame/screen"); return
        }

        // 确定目标屏幕和 frame
        let targetScreen: NSScreen
        let newFrame: CGRect

        switch action {
        case .nextDisplay:
            let screens = NSScreen.screens
            guard screens.count > 1 else { return }
            let idx = screens.firstIndex(of: currentScreen) ?? 0
            targetScreen = screens[(idx + 1) % screens.count]
            newFrame = maximizeRect(in: targetScreen.visibleFrame)
        default:
            targetScreen = currentScreen
            let vf = targetScreen.visibleFrame
            switch action {
            case .leftHalf:       newFrame = leftHalfRect(in: vf)
            case .rightHalf:      newFrame = rightHalfRect(in: vf)
            case .maximize:       newFrame = maximizeRect(in: vf)
            case .almostMaximize: newFrame = almostMaximizeRect(in: vf)
            case .reasonableSize: newFrame = reasonableSizeRect(in: vf)
            default:              return
            }
        }

        setFrame(win, newFrame)
        // 关键修复：bestEffort 使用目标屏幕，不是原始屏幕
        bestEffortAdjust(win, screen: targetScreen)
    }

    // MARK: 三级窗口查找

    private func findWindow(for app: NSRunningApplication) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var val: AnyObject?
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &val) == .success,
           let w = val { return (w as! AXUIElement) }
        if AXUIElementCopyAttributeValue(appEl, kAXMainWindowAttribute as CFString, &val) == .success,
           let w = val { return (w as! AXUIElement) }
        var windows: AnyObject?
        if AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windows) == .success,
           let list = windows as? [AXUIElement], !list.isEmpty { return list[0] }
        return nil
    }

    // MARK: 位置计算

    private func leftHalfRect(in vf: CGRect) -> CGRect {
        CGRect(x: vf.minX + gapSize, y: vf.minY + gapSize,
               width: vf.width / 2 - gapSize * 1.5, height: vf.height - gapSize * 2)
    }
    private func rightHalfRect(in vf: CGRect) -> CGRect {
        CGRect(x: vf.minX + vf.width / 2 + gapSize / 2, y: vf.minY + gapSize,
               width: vf.width / 2 - gapSize * 1.5, height: vf.height - gapSize * 2)
    }
    private func maximizeRect(in vf: CGRect) -> CGRect { vf }
    private func almostMaximizeRect(in vf: CGRect) -> CGRect {
        let w = vf.width * 0.9, h = vf.height * 0.9
        return CGRect(x: vf.minX + (vf.width - w) / 2, y: vf.minY + (vf.height - h) / 2, width: w, height: h)
    }
    private func reasonableSizeRect(in vf: CGRect) -> CGRect {
        let w = vf.width * 0.7, h = vf.height * 0.8
        return CGRect(x: vf.minX + (vf.width - w) / 2, y: vf.minY + (vf.height - h) / 2, width: w, height: h)
    }

    // MARK: AX Helpers

    private func getFrame(_ window: AXUIElement) -> CGRect? {
        var pVal: AnyObject?, sVal: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pVal) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sVal) == .success
        else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(pVal as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sVal as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var pos = frame.origin, size = frame.size
        guard let pv = AXValueCreate(.cgPoint, &pos), let sv = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
    }

    private func bestEffortAdjust(_ window: AXUIElement, screen: NSScreen) {
        guard var frame = getFrame(window) else { return }
        let vf = screen.visibleFrame
        var adjusted = false
        if frame.minX < vf.minX { frame.origin.x = vf.minX; adjusted = true }
        if frame.maxX > vf.maxX { frame.origin.x = vf.maxX - frame.width; adjusted = true }
        if frame.origin.y < vf.minY { frame.origin.y = vf.minY; adjusted = true }
        let axBottom = frame.origin.y + frame.height
        if axBottom > vf.origin.y + vf.size.height {
            frame.origin.y = vf.origin.y + vf.size.height - frame.size.height; adjusted = true
        }
        if adjusted { setFrame(window, frame) }
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
    }
}
