import Cocoa

// MARK: - 键盘事件处理器

/// 键盘事件处理器
/// 将 NSPanel 接收到的键盘事件转换为业务操作
/// 负责识别数字键 1-5、方向键、回车键和 ESC 键，并回调对应操作
final class KeyboardHandler {

    // MARK: - 回调闭包

    /// 选择指定索引（0-4），对应数字键 1-5
    var onSelectIndex: ((Int) -> Void)?

    /// 向上移动选择
    var onMoveUp: (() -> Void)?

    /// 向下移动选择
    var onMoveDown: (() -> Void)?

    /// 确认当前选择（回车键）
    var onConfirm: (() -> Void)?

    /// 取消/关闭窗口（ESC 键）
    var onCancel: (() -> Void)?

    // MARK: - KeyCode 常量定义

    /// macOS 键盘按键的 KeyCode 常量
    /// 参考: https://developer.apple.com/documentation/appkit/nsevent/1535851-function-key_unicodes
    private enum KeyCode {
        static let one:   UInt16 = 18   // 数字键 1
        static let two:   UInt16 = 19   // 数字键 2
        static let three: UInt16 = 20   // 数字键 3
        static let four:  UInt16 = 21   // 数字键 4
        static let five:  UInt16 = 23   // 数字键 5
        static let up:    UInt16 = 126  // 上箭头
        static let down:  UInt16 = 125  // 下箭头
        static let enter: UInt16 = 36   // 回车键
        static let esc:   UInt16 = 53   // ESC 键
    }

    // MARK: - 公开方法

    /// 处理键盘事件
    /// - Parameter event: NSEvent 键盘事件
    /// - Returns: 如果事件被消费返回 true，否则返回 false（事件继续传递）
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        // 只处理按键按下事件，忽略 keyUp 和 flagsChanged
        guard event.type == .keyDown else {
            return false
        }

        let keyCode = event.keyCode

        switch keyCode {
        case KeyCode.one:
            onSelectIndex?(0)
            return true

        case KeyCode.two:
            onSelectIndex?(1)
            return true

        case KeyCode.three:
            onSelectIndex?(2)
            return true

        case KeyCode.four:
            onSelectIndex?(3)
            return true

        case KeyCode.five:
            onSelectIndex?(4)
            return true

        case KeyCode.up:
            onMoveUp?()
            return true

        case KeyCode.down:
            onMoveDown?()
            return true

        case KeyCode.enter:
            onConfirm?()
            return true

        case KeyCode.esc:
            onCancel?()
            return true

        default:
            // 未识别的按键，不消费事件
            return false
        }
    }
}
