import Cocoa
import SwiftUI

// MARK: - 快速跳转弹出面板

/// 快速跳转弹出面板（单例管理）
///
/// 特性：
/// - 无边框 + 毛玻璃效果背景，圆角 12px
/// - 屏幕中央显示
/// - 失去焦点自动关闭
/// - 预创建窗口保证响应速度（首次弹出无延迟）
/// - 激活策略自动切换（从 LSUIElement 到 Regular）
/// - 支持键盘导航和鼠标点击选择
/// - Cmd+数字键 / Cmd+Enter 在访达中打开文件夹
final class QuickJumpPanel: NSObject {

    // MARK: - 单例

    /// 共享实例
    static let shared = QuickJumpPanel()

    // MARK: - 私有属性

    /// 底层 NSPanel 窗口
    private var panel: QuickJumpPanelWindow?

    /// SwiftUI 托管视图
    private var hostingView: NSHostingView<QuickJumpView>?

    /// 键盘事件处理器（强引用保持生命周期）
    private let keyboardHandler = KeyboardHandler()

    /// 当前使用的文件夹管理器引用
    private weak var folderManager: RecentFolderManager?

    /// 窗口是否已预创建
    private var isPanelCreated: Bool = false

    /// 窗口尺寸常量
    private enum Layout {
        /// 窗口宽度
        static let width: CGFloat = 500
        /// 窗口估算高度（标题 + 5 行 x 52 + 分隔线 + 底部提示）
        static let height: CGFloat = 320
        /// 窗口圆角半径
        static let cornerRadius: CGFloat = 12
    }

    /// 保存应用原始的激活策略，以便关闭时恢复
    private var originalActivationPolicy: NSApplication.ActivationPolicy?

    /// 选择回调
    private var onSelectCallback: ((RecentFolder) -> Void)?

    /// 取消回调
    private var onCancelCallback: (() -> Void)?

    /// 全局鼠标监控引用（检测点击在其他应用窗口上）
    private var globalMouseMonitor: Any?

    /// 本地鼠标监控引用（检测在当前应用内的点击）
    private var localMouseMonitor: Any?

    // MARK: - 初始化

    /// 私有初始化（单例模式）
    /// 应用启动时即预创建窗口，确保首次弹出无延迟
    private override init() {
        super.init()
        // 预创建窗口，但不显示
        createPanel()
    }

    // MARK: - 公开接口

    /// 窗口是否可见
    var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    /// 显示窗口
    /// - Parameters:
    ///   - folderManager: 最近文件夹数据管理器
    ///   - onSelect: 用户选择文件夹后的回调
    ///   - onCancel: 用户取消/关闭后的回调
    func show(
        folderManager: RecentFolderManager,
        onSelect: @escaping (RecentFolder) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // 如果窗口已在显示，先关闭再重新显示（刷新数据）
        if isVisible {
            close()
        }

        // 保存回调和数据管理器
        self.folderManager = folderManager
        self.onSelectCallback = onSelect
        self.onCancelCallback = onCancel

        // 刷新数据
        folderManager.refresh()

        // 确保窗口已创建
        if !isPanelCreated || panel == nil {
            createPanel()
        }

        // 更新 SwiftUI 视图内容
        updateHostingView(folderManager: folderManager)

        // 配置键盘事件处理
        setupKeyboardHandler()

        // 切换激活策略（从 LSUIElement / accessory 切换到 regular）
        // 这样窗口才能正常获取焦点和键盘事件
        activateApplication()

        // 设置窗口位置并显示
        positionWindow()
        panel?.makeKeyAndOrderFront(nil)

        // 注册失去焦点监听
        setupFocusMonitoring()
    }

    /// 关闭窗口
    func close() {
        // 移除焦点监听
        removeFocusMonitoring()

        // 关闭窗口
        panel?.orderOut(nil)

        // 恢复原始的激活策略（回到 LSUIElement / accessory 模式）
        restoreActivationPolicy()

        // 清理回调
        onSelectCallback = nil
        onCancelCallback = nil
    }

    // MARK: - 窗口创建与配置

    /// 创建并配置 NSPanel
    private func createPanel() {
        let newPanel = QuickJumpPanelWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Layout.width,
                height: Layout.height
            ),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // 浮动面板配置
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = true
        newPanel.isReleasedWhenClosed = false

        // 透明背景（由 NSVisualEffectView 提供实际背景）
        newPanel.backgroundColor = .clear

        // 允许点击背景穿透以支持点击外部关闭
        newPanel.isMovableByWindowBackground = false

        // 设置圆角
        newPanel.contentView?.wantsLayer = true
        newPanel.contentView?.layer?.cornerRadius = Layout.cornerRadius
        newPanel.contentView?.layer?.masksToBounds = true

        // 启用窗口阴影
        newPanel.hasShadow = true

        // 创建毛玻璃效果背景
        setupVisualEffectBackground(for: newPanel)

        // 设置窗口委托，监听失去焦点事件
        newPanel.delegate = self

        // 保存键盘处理器引用到窗口
        newPanel.keyboardHandler = keyboardHandler

        self.panel = newPanel
        self.isPanelCreated = true
    }

    /// 设置毛玻璃视觉效果背景
    private func setupVisualEffectBackground(for panel: NSWindow) {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .menu
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = Layout.cornerRadius
        visualEffectView.layer?.masksToBounds = true

        // 设置 autoresizing 以填充整个窗口
        visualEffectView.autoresizingMask = [.width, .height]

        // 将 NSVisualEffectView 设为 contentView 的底层背景
        if let contentView = panel.contentView {
            visualEffectView.frame = contentView.bounds
            contentView.addSubview(visualEffectView)
        } else {
            panel.contentView = visualEffectView
        }
    }

    /// 更新 SwiftUI 托管视图
    private func updateHostingView(folderManager: RecentFolderManager) {
        // 创建新的 SwiftUI 视图
        let quickJumpView = QuickJumpView(
            folderManager: folderManager,
            onSelect: { [weak self] folder in
                self?.handleSelect(folder: folder)
            },
            onCancel: { [weak self] in
                self?.handleCancel()
            }
        )

        // 创建或更新托管视图
        let newHostingView = NSHostingView(rootView: quickJumpView)
        newHostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: Layout.width,
            height: Layout.height
        )
        newHostingView.autoresizingMask = [.width, .height]

        // 移除旧的托管视图
        if let oldHostingView = hostingView {
            oldHostingView.removeFromSuperview()
        }

        // 添加到面板（位于 visualEffectView 之上）
        if let contentView = panel?.contentView {
            // 确保托管视图在最上层
            contentView.addSubview(newHostingView)
        }

        self.hostingView = newHostingView
    }

    // MARK: - 窗口位置

    /// 将窗口定位到屏幕中央
    private func positionWindow() {
        guard let panel = panel else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = panel.frame.size

        // 计算居中位置
        let originX = screenFrame.midX - windowSize.width / 2
        let originY = screenFrame.midY - windowSize.height / 2 + 40
            // 略微偏上，更符合视觉中心

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    // MARK: - 键盘处理

    /// 配置键盘事件处理器
    private func setupKeyboardHandler() {
        // 数字键 1-5：直接从文件夹管理器中取出对应索引的文件夹并确认跳转
        keyboardHandler.onSelectIndex = { [weak self] index in
            guard let self = self else { return }
            guard let folders = self.folderManager?.folders,
                  index < folders.count else { return }
            let folder = folders[index]
            self.handleSelect(folder: folder)
        }

        // Cmd+数字键 1-5：在访达中打开对应索引的文件夹
        keyboardHandler.onCmdSelectIndex = { [weak self] index in
            guard let self = self else { return }
            guard let folders = self.folderManager?.folders,
                  index < folders.count else { return }
            self.openInFinder(folders[index])
        }

        // 上下箭头：通过 NotificationCenter 通知 SwiftUI 视图更新选中状态
        keyboardHandler.onMoveUp = { [weak self] in
            self?.updateSelection(direction: -1)
        }

        keyboardHandler.onMoveDown = { [weak self] in
            self?.updateSelection(direction: 1)
        }

        // 回车确认：通过 NotificationCenter 通知 SwiftUI 视图执行确认
        keyboardHandler.onConfirm = { [weak self] in
            self?.confirmCurrentSelection()
        }

        // Cmd+Enter：在访达中打开当前选中项
        keyboardHandler.onCmdEnter = { [weak self] in
            guard let self = self else { return }
            guard self.folderManager?.folders != nil else { return }
            // 通过通知获取当前选中索引
            NotificationCenter.default.post(
                name: .quickJumpOpenFinder,
                object: nil
            )
        }

        // ESC 取消
        keyboardHandler.onCancel = { [weak self] in
            self?.handleCancel()
        }
    }

    /// 更新选中索引（通过重新创建视图或使用绑定）
    private func updateSelection(direction: Int) {
        NotificationCenter.default.post(
            name: .quickJumpMoveSelection,
            object: nil,
            userInfo: ["direction": direction]
        )
    }

    /// 确认当前选择
    private func confirmCurrentSelection() {
        NotificationCenter.default.post(
            name: .quickJumpConfirmSelection,
            object: nil
        )
    }

    // MARK: - 在访达中打开

    /// 在访达中打开指定文件夹
    private func openInFinder(_ folder: RecentFolder) {
        let url = URL(fileURLWithPath: folder.path)
        NSWorkspace.shared.open(url)
        // 关闭面板
        close()
    }

    // MARK: - 激活策略管理

    /// 激活应用以获取焦点
    private func activateApplication() {
        let app = NSApplication.shared

        // 保存当前策略（如果不是 regular 的话）
        if app.activationPolicy() != .regular {
            originalActivationPolicy = app.activationPolicy()
            app.setActivationPolicy(.regular)
        }

        // 激活应用（使窗口能够获取焦点）
        app.activate(ignoringOtherApps: true)
    }

    /// 恢复原始激活策略
    private func restoreActivationPolicy() {
        guard let originalPolicy = originalActivationPolicy else { return }
        NSApplication.shared.setActivationPolicy(originalPolicy)
        originalActivationPolicy = nil
    }

    // MARK: - 焦点监控

    /// 设置失去焦点监控和鼠标点击外部检测
    private func setupFocusMonitoring() {
        // 1. 全局鼠标监控：检测点击在其他应用的窗口上
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleCancel()
        }

        // 2. 本地鼠标监控：检测在当前应用内部、但不在面板窗口上的点击
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if let clickWindow = event.window, clickWindow != self.panel {
                self.handleCancel()
            }
            return event
        }
    }

    /// 移除焦点监控
    private func removeFocusMonitoring() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    // MARK: - 事件处理

    /// 处理文件夹选择
    private func handleSelect(folder: RecentFolder) {
        // 在 close() 清空回调前先捕获
        let callback = onSelectCallback
        close()
        DispatchQueue.main.async {
            callback?(folder)
        }
    }

    /// 处理取消操作
    private func handleCancel() {
        let callback = onCancelCallback
        close()
        DispatchQueue.main.async {
            callback?()
        }
    }
}

// MARK: - NSWindowDelegate

extension QuickJumpPanel: NSWindowDelegate {

    /// 窗口失去 Key 状态时自动关闭
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if self?.isVisible == true && self?.panel?.isKeyWindow == false {
                self?.handleCancel()
            }
        }
    }

    /// 窗口即将关闭
    func windowWillClose(_ notification: Notification) {
        handleCancel()
    }
}

// MARK: - 自定义 NSPanel 窗口

/// 自定义 NSPanel，用于拦截键盘事件
final class QuickJumpPanelWindow: NSPanel {

    /// 键盘事件处理器引用
    weak var keyboardHandler: KeyboardHandler?

    /// 拦截键盘事件
    override func keyDown(with event: NSEvent) {
        if let handler = keyboardHandler, handler.handleKeyEvent(event) {
            return
        }
        super.keyDown(with: event)
    }

    /// 拦截标志键事件（用于防止系统默认快捷键干扰）
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
    }

    /// 允许成为 Key 窗口（接收键盘输入）
    override var canBecomeKey: Bool {
        return true
    }

    /// 允许成为 Main 窗口
    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - Notification 名称扩展

extension Notification.Name {

    /// 移动选中位置通知（userInfo 包含 direction: -1 向上, 1 向下）
    static let quickJumpMoveSelection = Notification.Name("quickJumpMoveSelection")

    /// 确认当前选择通知
    static let quickJumpConfirmSelection = Notification.Name("quickJumpConfirmSelection")

    /// 在访达中打开当前选中项通知
    static let quickJumpOpenFinder = Notification.Name("quickJumpOpenFinder")
}
