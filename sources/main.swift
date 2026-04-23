import Cocoa

/// QuickFolderJump 应用入口点
/// 使用 @main 属性标记为程序入口，创建 AppDelegate 并启动应用主循环
@main
struct QuickFolderJumpApp {
    static func main() {
        // 创建应用委托实例，负责协调所有模块
        let delegate = AppDelegate()
        
        // 设置应用委托
        NSApplication.shared.delegate = delegate
        
        // 运行应用主事件循环（不会返回直到应用终止）
        NSApplication.shared.run()
    }
}
