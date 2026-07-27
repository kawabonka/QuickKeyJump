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

    // MARK: Execute

    func execute(_ action: WindowAction) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            print("[QKJ] WM: no frontmost application"); return
        }
        guard let win = findWindow(for: frontApp) else {
            print("[QKJ] WM: no window for \(frontApp.localizedName ?? "?")"); return
        }
        // getFrame 返回 CG 坐标（AX 原生），转为 AppKit 用于内部计算
        guard let cgFrame = getFrame(win),
              let axFrame = cgToAppKit(cgFrame),
              let currentScreen = screenContaining(axFrame) else {
            print("[QKJ] WM: cannot get frame/screen"); return
        }

        let targetScreen: NSScreen
        let targetFrameAppKit: CGRect

        switch action {
        case .nextDisplay:
            let screens = NSScreen.screens
            guard screens.count > 1 else { return }
            let idx = screens.firstIndex(of: currentScreen) ?? 0
            targetScreen = screens[(idx + 1) % screens.count]
            targetFrameAppKit = maximizeRect(in: targetScreen.visibleFrame)
        default:
            targetScreen = currentScreen
            let vf = targetScreen.visibleFrame
            switch action {
            case .leftHalf:       targetFrameAppKit = leftHalfRect(in: vf)
            case .rightHalf:      targetFrameAppKit = rightHalfRect(in: vf)
            case .maximize:       targetFrameAppKit = maximizeRect(in: vf)
            case .almostMaximize: targetFrameAppKit = almostMaximizeRect(in: vf)
            case .reasonableSize: targetFrameAppKit = reasonableSizeRect(in: vf)
            default:              return
            }
        }

        // AppKit → CG 坐标转换后设置
        setFrame(win, appKitToCG(targetFrameAppKit))
        bestEffortAdjust(win, screen: targetScreen)
    }

    // MARK: 坐标转换（AppKit 原点左下 ↔ AX/CG 原点左上）

    private func appKitToCG(_ r: CGRect) -> CGRect {
        // NSScreen.screens 包含所有屏幕，找到包含该 frame 的屏幕来计算高度
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(r) }) ?? NSScreen.main else {
            return r
        }
        let sh = screen.frame.height
        return CGRect(x: r.origin.x, y: sh - r.origin.y - r.height, width: r.width, height: r.height)
    }

    private func cgToAppKit(_ r: CGRect) -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(r) }) ?? NSScreen.main else {
            return nil
        }
        let sh = screen.frame.height
        return CGRect(x: r.origin.x, y: sh - r.origin.y - r.height, width: r.width, height: r.height)
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

    // MARK: 位置计算（AppKit 坐标系）

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

    // MARK: AX Helpers（CG 坐标系）

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

    /// bestEffortAdjust 读取和写入均使用 CG 坐标，visibleFrame 需转为 CG 后比较
    private func bestEffortAdjust(_ window: AXUIElement, screen: NSScreen) {
        guard var cgFrame = getFrame(window) else { return }
        let vfAppKit = screen.visibleFrame
        let vf = appKitToCG(CGRect(x: vfAppKit.minX, y: vfAppKit.minY,
                                    width: vfAppKit.width, height: vfAppKit.height))
        var adjusted = false
        if cgFrame.minX < vf.minX { cgFrame.origin.x = vf.minX; adjusted = true }
        if cgFrame.maxX > vf.maxX { cgFrame.origin.x = vf.maxX - cgFrame.width; adjusted = true }
        if cgFrame.minY < vf.minY { cgFrame.origin.y = vf.minY; adjusted = true }
        if cgFrame.maxY > vf.maxY { cgFrame.origin.y = vf.maxY - cgFrame.height; adjusted = true }
        if adjusted { setFrame(window, cgFrame) }
    }

    /// screenContaining 接受 AppKit 坐标
    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
    }
}
