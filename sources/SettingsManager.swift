import Foundation

extension KeyboardShortcuts.Name {
    static let quickJump = Self("quickJump", default: .init(.g, modifiers: [.option, .command]))
    static let fileManager = Self("fileManager", default: .init(.e, modifiers: [.command]))
    static let windowLeftHalf = Self("windowLeftHalf", default: .init(.leftArrow, modifiers: [.control, .shift]))
    static let windowRightHalf = Self("windowRightHalf", default: .init(.rightArrow, modifiers: [.control, .shift]))
    static let windowMaximize = Self("windowMaximize", default: .init(.upArrow, modifiers: [.control, .option]))
    static let windowAlmostMaximize = Self("windowAlmostMaximize", default: .init(.upArrow, modifiers: [.option, .command]))
    static let windowNextDisplay = Self("windowNextDisplay", default: .init(.rightArrow, modifiers: [.control, .option]))
    static let windowReasonableSize = Self("windowReasonableSize", default: .init(.downArrow, modifiers: [.control, .option]))
}

enum ActionType: String, CaseIterable {
    case quickJump, fileManager
    case windowLeftHalf, windowRightHalf, windowMaximize
    case windowAlmostMaximize, windowNextDisplay, windowReasonableSize

    var name: KeyboardShortcuts.Name {
        switch self {
        case .quickJump:           return .quickJump
        case .fileManager:      return .fileManager
        case .windowLeftHalf:      return .windowLeftHalf
        case .windowRightHalf:     return .windowRightHalf
        case .windowMaximize:      return .windowMaximize
        case .windowAlmostMaximize: return .windowAlmostMaximize
        case .windowNextDisplay:   return .windowNextDisplay
        case .windowReasonableSize: return .windowReasonableSize
        }
    }

    var displayName: String {
        switch self {
        case .quickJump: L("快速跳转", "Quick Jump")
        case .fileManager: L("文件管理器", "File Manager")
        case .windowLeftHalf: L("左半屏", "Left Half")
        case .windowRightHalf: L("右半屏", "Right Half")
        case .windowMaximize: L("最大化", "Maximize")
        case .windowAlmostMaximize: L("几乎最大化", "Almost Maximize")
        case .windowNextDisplay: L("下一显示器", "Next Display")
        case .windowReasonableSize: L("合适大小", "Reasonable Size")
        }
    }

    var description: String {
        switch self {
        case .quickJump: L("弹出最近文件夹面板", "Show recent Finder folders")
        case .fileManager: L("打开 Finder 文件管理器", "Open Finder home directory")
        case .windowLeftHalf: L("窗口占据屏幕左半区域", "Window occupies left half of screen")
        case .windowRightHalf: L("窗口占据屏幕右半区域", "Window occupies right half of screen")
        case .windowMaximize: L("窗口最大化", "Maximize the window")
        case .windowAlmostMaximize: L("窗口几乎占满屏幕", "Window almost fills the screen")
        case .windowNextDisplay: L("将窗口移至下一显示器", "Move window to next display")
        case .windowReasonableSize: L("缩放至合适阅读尺寸", "Resize to comfortable reading size")
        }
    }

    var icon: String {
        switch self {
        case .quickJump: "folder.fill"
        case .fileManager: "folder.fill"
        case .windowLeftHalf: "rectangle.lefthalf.inset.filled"
        case .windowRightHalf: "rectangle.righthalf.inset.filled"
        case .windowMaximize: "rectangle.inset.filled"
        case .windowAlmostMaximize: "rectangle.center.inset.filled"
        case .windowNextDisplay: "rectangle.2.swap"
        case .windowReasonableSize: "rectangle.portrait.center.inset.filled"
        }
    }

    var windowAction: WindowAction? {
        switch self {
        case .windowLeftHalf:      return .leftHalf
        case .windowRightHalf:     return .rightHalf
        case .windowMaximize:      return .maximize
        case .windowAlmostMaximize: return .almostMaximize
        case .windowNextDisplay:   return .nextDisplay
        case .windowReasonableSize: return .reasonableSize
        default: return nil
        }
    }
}
extension Notification.Name { static let triggerAction = Notification.Name("QKJ_triggerAction") }
extension Notification.Name { static let languageChanged = Notification.Name("QKJ_languageChanged") }
