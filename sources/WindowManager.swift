import Cocoa

enum WindowAction: String, CaseIterable {
    case leftHalf, rightHalf, maximize, almostMaximize, nextDisplay, reasonableSize

    var displayName: String {
        switch self {
        case .leftHalf: "左半屏"
        case .rightHalf: "右半屏"
        case .maximize: "最大化"
        case .almostMaximize: "几乎最大化"
        case .nextDisplay: "下一显示器"
        case .reasonableSize: "合适大小"
        }
    }

    var icon: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.inset.filled"
        case .rightHalf: "rectangle.righthalf.inset.filled"
        case .maximize: "rectangle.inset.filled"
        case .almostMaximize: "rectangle.center.inset.filled"
        case .nextDisplay: "rectangle.2.swap"
        case .reasonableSize: "rectangle.portrait.center.inset.filled"
        }
    }

    var shortcut: String { String(Self.allCases.firstIndex(of: self)! + 1) }
}

final class WindowManager {
    static let shared = WindowManager()

    func execute(_ action: WindowAction) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var w: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &w) == .success,
              let window = w else { return }
        let win = window as! AXUIElement
        switch action {
        case .leftHalf: resizeToLeftHalf(win)
        case .rightHalf: resizeToRightHalf(win)
        case .maximize: resizeToMaximize(win)
        case .almostMaximize: resizeToAlmostMaximize(win)
        case .nextDisplay: moveToNextDisplay(win)
        case .reasonableSize: resizeToReasonableSize(win)
        }
    }

    private func currentScreen(_ win: AXUIElement) -> NSScreen? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &v) == .success else { return nil }
        var pt = CGPoint.zero; AXValueGetValue(v as! AXValue, .cgPoint, &pt)
        return NSScreen.screens.first { $0.frame.contains(pt) } ?? NSScreen.main
    }

    private func set(_ win: AXUIElement, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        var pos = CGPoint(x: x, y: y), siz = CGSize(width: w, height: h)
        AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!)
        AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &siz)!)
    }

    private func resizeToLeftHalf(_ win: AXUIElement) {
        guard let scr = currentScreen(win) else { return }
        let f = scr.visibleFrame
        set(win, x: f.minX, y: f.minY, w: f.width / 2, h: f.height)
    }

    private func resizeToRightHalf(_ win: AXUIElement) {
        guard let scr = currentScreen(win) else { return }
        let f = scr.visibleFrame
        set(win, x: f.minX + f.width / 2, y: f.minY, w: f.width / 2, h: f.height)
    }

    private func resizeToMaximize(_ win: AXUIElement) {
        guard let scr = currentScreen(win) else { return }
        let f = scr.visibleFrame
        set(win, x: f.minX, y: f.minY, w: f.width, h: f.height)
    }

    private func resizeToAlmostMaximize(_ win: AXUIElement) {
        guard let scr = currentScreen(win) else { return }
        let f = scr.visibleFrame; let m: CGFloat = 20
        set(win, x: f.minX + m, y: f.minY + m, w: f.width - m * 2, h: f.height - m * 2)
    }

    private func resizeToReasonableSize(_ win: AXUIElement) {
        guard let scr = currentScreen(win) else { return }
        let f = scr.visibleFrame
        let w = f.width * 0.7, h = f.height * 0.8
        set(win, x: f.minX + (f.width - w) / 2, y: f.minY + (f.height - h) / 2, w: w, h: h)
    }

    private func moveToNextDisplay(_ win: AXUIElement) {
        let screens = NSScreen.screens
        guard screens.count > 1, let cur = currentScreen(win) else { return }
        let idx = (screens.firstIndex(of: cur) ?? 0) + 1
        let f = screens[idx % screens.count].visibleFrame
        set(win, x: f.minX, y: f.minY, w: f.width, h: f.height)
    }
}
