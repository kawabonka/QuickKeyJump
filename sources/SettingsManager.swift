import Foundation
import Carbon

// MARK: - Action Types

enum ActionType: String, CaseIterable {
    case quickJump = "quickJump"
    case defaultBrowser = "defaultBrowser"
    case windowManagement = "windowManagement"

    var displayName: String {
        switch self {
        case .quickJump: return "快速跳转"
        case .defaultBrowser: return "默认浏览器"
        case .windowManagement: return "窗口管理"
        }
    }

    var description: String {
        switch self {
        case .quickJump: return "弹出最近文件夹面板，快速跳转到目标目录"
        case .defaultBrowser: return "打开系统默认浏览器"
        case .windowManagement: return "左半屏 / 右半屏 / 最大化 / 下一显示器"
        }
    }

    var icon: String {
        switch self {
        case .quickJump: return "folder.fill"
        case .defaultBrowser: return "safari.fill"
        case .windowManagement: return "rectangle.3.group"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .quickJump:
            return Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: UInt(optionKey | cmdKey))
        case .defaultBrowser:
            return Shortcut(keyCode: UInt16(kVK_ANSI_E), modifiers: UInt(cmdKey))
        case .windowManagement:
            return Shortcut(keyCode: UInt16(kVK_ANSI_Z), modifiers: UInt(optionKey | cmdKey))
        }
    }

    /// 每个 ActionType 对应的 Carbon 热键唯一 ID（signature 低 16 位）
    var hotKeyID: UInt32 {
        switch self {
        case .quickJump: return 1
        case .defaultBrowser: return 2
        case .windowManagement: return 3
        }
    }
}

// MARK: - Shortcut Model

struct Shortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt

    var displayString: String {
        "\(modifierDisplayString)\(keyCodeDisplayString)"
    }

    private var modifierDisplayString: String {
        var parts: [String] = []
        if modifiers & UInt(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    private var keyCodeDisplayString: String {
        SettingsManager.keyCodeToChar(keyCode)
    }

    var hasModifiers: Bool {
        modifiers != 0
    }
}

// MARK: - Settings Manager

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let shortcutsKey = "com.quickkeyjump.shortcuts"

    @Published private(set) var shortcuts: [ActionType: Shortcut] = [:]

    private init() {
        load()
    }

    // MARK: Shortcut Access

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

    // MARK: Persistence

    private func save() {
        let encoded = shortcuts.mapValues { ["keyCode": $0.keyCode, "modifiers": $0.modifiers] }
        defaults.set(encoded, forKey: shortcutsKey)
        defaults.synchronize()
    }

    private func load() {
        guard let encoded = defaults.dictionary(forKey: shortcutsKey) as? [String: [String: UInt]]
        else {
            for action in ActionType.allCases {
                shortcuts[action] = action.defaultShortcut
            }
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

    // MARK: Key Code Display

    static func keyCodeToChar(_ keyCode: UInt16) -> String {
        switch keyCode {
        case UInt16(kVK_ANSI_A): return "A"
        case UInt16(kVK_ANSI_B): return "B"
        case UInt16(kVK_ANSI_C): return "C"
        case UInt16(kVK_ANSI_D): return "D"
        case UInt16(kVK_ANSI_E): return "E"
        case UInt16(kVK_ANSI_F): return "F"
        case UInt16(kVK_ANSI_G): return "G"
        case UInt16(kVK_ANSI_H): return "H"
        case UInt16(kVK_ANSI_I): return "I"
        case UInt16(kVK_ANSI_J): return "J"
        case UInt16(kVK_ANSI_K): return "K"
        case UInt16(kVK_ANSI_L): return "L"
        case UInt16(kVK_ANSI_M): return "M"
        case UInt16(kVK_ANSI_N): return "N"
        case UInt16(kVK_ANSI_O): return "O"
        case UInt16(kVK_ANSI_P): return "P"
        case UInt16(kVK_ANSI_Q): return "Q"
        case UInt16(kVK_ANSI_R): return "R"
        case UInt16(kVK_ANSI_S): return "S"
        case UInt16(kVK_ANSI_T): return "T"
        case UInt16(kVK_ANSI_U): return "U"
        case UInt16(kVK_ANSI_V): return "V"
        case UInt16(kVK_ANSI_W): return "W"
        case UInt16(kVK_ANSI_X): return "X"
        case UInt16(kVK_ANSI_Y): return "Y"
        case UInt16(kVK_ANSI_S): return "Z"
        case UInt16(kVK_ANSI_0): return "0"
        case UInt16(kVK_ANSI_1): return "1"
        case UInt16(kVK_ANSI_2): return "2"
        case UInt16(kVK_ANSI_3): return "3"
        case UInt16(kVK_ANSI_4): return "4"
        case UInt16(kVK_ANSI_5): return "5"
        case UInt16(kVK_ANSI_6): return "6"
        case UInt16(kVK_ANSI_7): return "7"
        case UInt16(kVK_ANSI_8): return "8"
        case UInt16(kVK_ANSI_9): return "9"
        case UInt16(kVK_Space): return "␣"
        case UInt16(kVK_Return): return "↵"
        case UInt16(kVK_Tab): return "⇥"
        case UInt16(kVK_Delete): return "⌫"
        case UInt16(kVK_Escape): return "Esc"
        case UInt16(kVK_ForwardDelete): return "⌦"
        case UInt16(kVK_UpArrow): return "↑"
        case UInt16(kVK_DownArrow): return "↓"
        case UInt16(kVK_LeftArrow): return "←"
        case UInt16(kVK_RightArrow): return "→"
        case UInt16(kVK_F1): return "F1"
        case UInt16(kVK_F2): return "F2"
        case UInt16(kVK_F3): return "F3"
        case UInt16(kVK_F4): return "F4"
        case UInt16(kVK_F5): return "F5"
        case UInt16(kVK_F6): return "F6"
        case UInt16(kVK_F7): return "F7"
        case UInt16(kVK_F8): return "F8"
        case UInt16(kVK_F9): return "F9"
        case UInt16(kVK_F10): return "F10"
        case UInt16(kVK_F11): return "F11"
        case UInt16(kVK_F12): return "F12"
        case UInt16(kVK_ANSI_Equal): return "="
        case UInt16(kVK_ANSI_Minus): return "-"
        case UInt16(kVK_ANSI_LeftBracket): return "["
        case UInt16(kVK_ANSI_RightBracket): return "]"
        case UInt16(kVK_ANSI_Slash): return "/"
        case UInt16(kVK_ANSI_Backslash): return "\\"
        case UInt16(kVK_ANSI_Semicolon): return ";"
        case UInt16(kVK_ANSI_Quote): return "'"
        case UInt16(kVK_ANSI_Comma): return ","
        case UInt16(kVK_ANSI_Period): return "."
        default: return "?"
        }
    }
}
