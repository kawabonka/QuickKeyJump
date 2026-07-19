import Foundation
import Carbon

enum ActionType: String, CaseIterable {
    case quickJump = "quickJump"
    case defaultBrowser = "defaultBrowser"
    case windowLeftHalf = "windowLeftHalf"
    case windowRightHalf = "windowRightHalf"
    case windowMaximize = "windowMaximize"
    case windowAlmostMaximize = "windowAlmostMaximize"
    case windowNextDisplay = "windowNextDisplay"
    case windowReasonableSize = "windowReasonableSize"

    var displayName: String {
        switch self {
        case .quickJump: return "快速跳转"
        case .defaultBrowser: return "默认浏览器"
        case .windowLeftHalf: return "左半屏"
        case .windowRightHalf: return "右半屏"
        case .windowMaximize: return "最大化"
        case .windowAlmostMaximize: return "几乎最大化"
        case .windowNextDisplay: return "下一显示器"
        case .windowReasonableSize: return "合适大小"
        }
    }

    var description: String {
        switch self {
        case .quickJump: return "弹出最近文件夹面板"
        case .defaultBrowser: return "打开系统默认浏览器"
        case .windowLeftHalf: return "窗口占据屏幕左半区域"
        case .windowRightHalf: return "窗口占据屏幕右半区域"
        case .windowMaximize: return "窗口最大化"
        case .windowAlmostMaximize: return "窗口几乎占满屏幕"
        case .windowNextDisplay: return "将窗口移至下一显示器"
        case .windowReasonableSize: return "缩放至合适阅读尺寸"
        }
    }

    var icon: String {
        switch self {
        case .quickJump: return "folder.fill"
        case .defaultBrowser: return "safari.fill"
        case .windowLeftHalf: return "rectangle.lefthalf.inset.filled"
        case .windowRightHalf: return "rectangle.righthalf.inset.filled"
        case .windowMaximize: return "rectangle.inset.filled"
        case .windowAlmostMaximize: return "rectangle.center.inset.filled"
        case .windowNextDisplay: return "rectangle.2.swap"
        case .windowReasonableSize: return "rectangle.portrait.center.inset.filled"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .quickJump:
            return Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: UInt(optionKey | cmdKey))
        case .defaultBrowser:
            return Shortcut(keyCode: UInt16(kVK_ANSI_E), modifiers: UInt(cmdKey))
        case .windowLeftHalf:
            return Shortcut(keyCode: 123, modifiers: UInt(controlKey | shiftKey))
        case .windowRightHalf:
            return Shortcut(keyCode: 124, modifiers: UInt(controlKey | shiftKey))
        case .windowMaximize:
            return Shortcut(keyCode: 126, modifiers: UInt(controlKey | optionKey))
        case .windowAlmostMaximize:
            return Shortcut(keyCode: 126, modifiers: UInt(optionKey | cmdKey))
        case .windowNextDisplay:
            return Shortcut(keyCode: 124, modifiers: UInt(controlKey | optionKey))
        case .windowReasonableSize:
            return Shortcut(keyCode: 125, modifiers: UInt(controlKey | optionKey))
        }
    }

    var hotKeyID: UInt32 {
        UInt32(Self.allCases.firstIndex(of: self)!) + 1
    }
}

struct Shortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt

    var displayString: String {
        modifierDisplayString + keyCodeDisplayString
    }

    private var modifierDisplayString: String {
        var parts: [String] = []
        if modifiers & UInt(controlKey) != 0 { parts.append("\u{2303}") }
        if modifiers & UInt(optionKey) != 0 { parts.append("\u{2325}") }
        if modifiers & UInt(shiftKey) != 0 { parts.append("\u{21E7}") }
        if modifiers & UInt(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    private var keyCodeDisplayString: String {
        SettingsManager.keyCodeToChar(keyCode)
    }
}

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let shortcutsKey = "com.quickkeyjump.shortcuts"

    @Published private(set) var shortcuts: [ActionType: Shortcut] = [:]

    private init() { load() }

    func shortcut(for action: ActionType) -> Shortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func setShortcut(_ shortcut: Shortcut, for action: ActionType) {
        shortcuts[action] = shortcut
        save()
    }

    func resetAllToDefaults() {
        shortcuts.removeAll()
        for action in ActionType.allCases {
            shortcuts[action] = action.defaultShortcut
        }
        save()
        objectWillChange.send()
    }

    private func save() {
        let encoded = shortcuts.mapValues { ["keyCode": $0.keyCode, "modifiers": $0.modifiers] }
        defaults.set(encoded, forKey: shortcutsKey)
        defaults.synchronize()
    }

    private func load() {
        guard let encoded = defaults.dictionary(forKey: shortcutsKey) as? [String: [String: UInt]]
        else {
            for action in ActionType.allCases { shortcuts[action] = action.defaultShortcut }
            return
        }
        for action in ActionType.allCases {
            if let dict = encoded[action.rawValue],
               let keyCode = dict["keyCode"],
               let modifiers = dict["modifiers"] {
                shortcuts[action] = Shortcut(keyCode: UInt16(keyCode), modifiers: modifiers)
            } else {
                shortcuts[action] = action.defaultShortcut
            }
        }
    }

    static func keyCodeToChar(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"
        case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 31: return "O"; case 32: return "U"; case 34: return "I"
        case 35: return "P"; case 37: return "L"; case 38: return "J"; case 40: return "K"
        case 45: return "N"; case 46: return "M"; case 29: return "0"; case 18: return "1"
        case 19: return "2"; case 20: return "3"; case 21: return "4"; case 23: return "5"
        case 22: return "6"; case 26: return "7"; case 28: return "8"; case 25: return "9"
        case 49: return "\u{2423}"; case 36: return "\u{21B5}"; case 48: return "\u{21E5}"
        case 51: return "\u{232B}"; case 53: return "Esc"; case 117: return "\u{2326}"
        case 126: return "\u{2191}"; case 125: return "\u{2193}"
        case 123: return "\u{2190}"; case 124: return "\u{2192}"
        case 122: return "F1"; case 120: return "F2"; case 99: return "F3"
        case 118: return "F4"; case 96: return "F5"; case 97: return "F6"
        case 98: return "F7"; case 100: return "F8"; case 101: return "F9"
        case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
        case 24: return "="; case 27: return "-"; case 33: return "["
        case 30: return "]"; case 44: return "/"; case 42: return "\\"
        case 41: return ";"; case 39: return "'"; case 43: return ","
        case 47: return "."
        default: return "?"
        }
    }
}
