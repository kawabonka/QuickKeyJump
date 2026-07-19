import Cocoa

// MARK: - 窗口操作类型

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

// MARK: - 窗口管理器（参照 Rectangle 实现）

final class WindowManager {
    static let shared = WindowManager()
    private let gapSize: CGFloat = 8

    private init() {}

    func execute(_ action: WindowAction) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var w: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &w) == .success,
              let window = w else { return }
        let win = window as! AXUIElement

        // 获取窗口当前位置
        guard let currentFrame = getFrame(win),
              let screen = screenContaining(currentFrame) else { return }

        let vf = screen.visibleFrame  // 已扣除菜单栏/Dock

        let newFrame: CGRect
        switch action {
        case .leftHalf:       newFrame = leftHalfRect(in: vf)
        case .rightHalf:      newFrame = rightHalfRect(in: vf)
        case .maximize:       newFrame = maximizeRect(in: vf)
        case .almostMaximize: newFrame = almostMaximizeRect(in: vf)
        case .nextDisplay:    newFrame = nextDisplayRect(from: screen, current: currentFrame)
        case .reasonableSize: newFrame = reasonableSizeRect(in: vf)
        }

        setFrame(win, newFrame)

        // Rectangle-style best-effort: ensure window fits on screen
        bestEffortAdjust(win, screen: screen)
    }

    // MARK: 位置计算（参照 Rectangle LeftRightHalfCalculation）

    private func leftHalfRect(in vf: CGRect) -> CGRect {
        CGRect(
            x: vf.minX + gapSize,
            y: vf.minY + gapSize,
            width: vf.width / 2 - gapSize * 1.5,
            height: vf.height - gapSize * 2
        )
    }

    private func rightHalfRect(in vf: CGRect) -> CGRect {
        CGRect(
            x: vf.minX + vf.width / 2 + gapSize / 2,
            y: vf.minY + gapSize,
            width: vf.width / 2 - gapSize * 1.5,
            height: vf.height - gapSize * 2
        )
    }

    private func maximizeRect(in vf: CGRect) -> CGRect {
        vf
    }

    /// 参照 Rectangle AlmostMaximizeCalculation: 默认 90% 宽高
    private func almostMaximizeRect(in vf: CGRect) -> CGRect {
        let ratio: CGFloat = 0.9
        let w = vf.width * ratio
        let h = vf.height * ratio
        return CGRect(
            x: vf.minX + (vf.width - w) / 2,
            y: vf.minY + (vf.height - h) / 2,
            width: w, height: h
        )
    }

    /// 参照 Rectangle CenterCalculation: 窗口居中，70% 宽 × 80% 高
    private func reasonableSizeRect(in vf: CGRect) -> CGRect {
        let w = vf.width * 0.7
        let h = vf.height * 0.8
        return CGRect(
            x: vf.minX + (vf.width - w) / 2,
            y: vf.minY + (vf.height - h) / 2,
            width: w, height: h
        )
    }

    /// 参照 Rectangle NextPrevDisplayCalculation
    private func nextDisplayRect(from currentScreen: NSScreen, current frame: CGRect) -> CGRect {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return frame }
        let idx = screens.firstIndex(of: currentScreen) ?? 0
        let next = screens[(idx + 1) % screens.count]
        return maximizeRect(in: next.visibleFrame)
    }

    // MARK: AX API（参照 Rectangle StandardWindowMover）

    private func getFrame(_ window: AXUIElement) -> CGRect? {
        var posVal: AnyObject?, sizeVal: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeVal) == .success
        else { return nil }

        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var pos = frame.origin, size = frame.size
        guard let pv = AXValueCreate(.cgPoint, &pos),
              let sv = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
    }

    /// Rectangle-style best-effort: 如果窗口超出屏幕边界，往回拉
    private func bestEffortAdjust(_ window: AXUIElement, screen: NSScreen) {
        guard var frame = getFrame(window) else { return }
        let vf = screen.visibleFrame
        var adjusted = false

        if frame.minX < vf.minX { frame.origin.x = vf.minX; adjusted = true }
        if frame.maxX > vf.maxX { frame.origin.x = vf.maxX - frame.width; adjusted = true }
        // AX 坐标系 Y 轴向下，需翻转比较
        // Rectangle 使用 screenFlipped: CGRect → 翻转 Y → 计算 → 翻转回
        // 简化：直接比较 flipped 坐标
        // frame 的 bottom (在 AppKit 坐标中) = screen.maxY - (frame.origin.y + frame.height) 
        // AppKit: y=0 at bottom. AX: y=0 at top.
        // frame.origin.y (AX) 是顶部距离。窗口底部 = frame.origin.y + frame.height
        if frame.origin.y < vf.minY { frame.origin.y = vf.minY; adjusted = true }
        let axBottom = frame.origin.y + frame.height
        // visibleFrame uses AppKit coordinates (origin at bottom-left)
        // AX uses CG coordinates (origin at top-left)
        // Conversion: axY = screenHeight - appKitY - height
        // For simplicity, use a safe approach
        if axBottom > vf.origin.y + vf.size.height {
            frame.origin.y = vf.origin.y + vf.size.height - frame.size.height
            adjusted = true
        }

        if adjusted { setFrame(window, frame) }
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
    }
}
