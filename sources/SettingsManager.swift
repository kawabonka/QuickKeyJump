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
        case .quickJump: "快速跳转"
        case .fileManager: "文件管理器"
        case .windowLeftHalf: "左半屏"
        case .windowRightHalf: "右半屏"
        case .windowMaximize: "最大化"
        case .windowAlmostMaximize: "几乎最大化"
        case .windowNextDisplay: "下一显示器"
        case .windowReasonableSize: "合适大小"
        }
    }

    var description: String {
        switch self {
        case .quickJump: "弹出最近文件夹面板"
        case .fileManager: "打开 Finder 文件管理器"
        case .windowLeftHalf: "窗口占据屏幕左半区域"
        case .windowRightHalf: "窗口占据屏幕右半区域"
        case .windowMaximize: "窗口最大化"
        case .windowAlmostMaximize: "窗口几乎占满屏幕"
        case .windowNextDisplay: "将窗口移至下一显示器"
        case .windowReasonableSize: "缩放至合适阅读尺寸"
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
