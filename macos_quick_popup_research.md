# macOS 快速弹出UI窗口和全局快捷键实现调研报告

## 目录
1. [NSPanel vs NSWindow 选择](#1-nspanel-vs-nswindow-选择)
2. [窗口焦点管理](#2-窗口焦点管理)
3. [全局快捷键注册](#3-全局快捷键注册)
4. [键盘事件处理](#4-键盘事件处理)
5. [UI设计建议](#5-ui设计建议)
6. [完整项目代码示例](#6-完整项目代码示例)
7. [方案对比和推荐组合](#7-方案对比和推荐组合)

---

## 1. NSPanel vs NSWindow 选择

### 推荐：使用 NSPanel

对于快速目录跳转工具的弹出式UI，**强烈推荐使用 NSPanel** 而非 NSWindow。原因如下：

| 特性 | NSPanel | NSWindow |
|------|---------|----------|
| 专门用于辅助窗口 | ✅ 是 | ❌ 否 |
| Non-activating 模式 | ✅ `.nonactivatingPanel` | ❌ 不支持 |
| 自动浮动层级 | ✅ `isFloatingPanel` | 需手动设置 level |
| HUD 窗口样式 | ✅ `.hudWindow` | ❌ 不支持 |
| 失去焦点自动隐藏 | ✅ `hidesOnDeactivate` | 需手动实现 |
| 成为Key窗口控制 | ✅ `becomesKeyOnlyIfNeeded` | 有限控制 |

### 推荐的 NSPanel 配置

对于这种快速弹出工具（类似 Spotlight / Listary 风格），推荐以下配置：

```swift
class QuickJumpPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 280),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // 核心配置
        self.isFloatingPanel = true
        self.level = .floating                      // 浮动在其他窗口之上
        self.becomesKeyOnlyIfNeeded = false         // 需要立即获取键盘焦点
        self.hidesOnDeactivate = true               // 失去焦点时自动隐藏
        self.isReleasedWhenClosed = false           // 关闭时不释放
        self.isOpaque = false                       // 允许透明背景
        self.backgroundColor = .clear               // 背景透明（配合NSVisualEffectView）
        self.hasShadow = true                       // 窗口阴影
        self.animationBehavior = .utilityWindow     // 弹出动画
        
        // 多Space支持 + 全屏辅助
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // 内容视图
        self.contentView = contentView
    }
}
```

### styleMask 选项详解

```swift
// 方案A: 无边框 + 毛玻璃效果（推荐）
[.borderless, .nonactivatingPanel, .fullSizeContentView]

// 方案B: HUD风格（类似系统控制面板）
[.hudWindow, .utilityWindow, .nonactivatingPanel, .fullSizeContentView]

// 方案C: 带标题栏（如需标题）
[.titled, .closable, .nonactivatingPanel, .fullSizeContentView]
```

**推荐方案A** — 无边框样式最符合 Listary/Spotlight 风格。

### 窗口层级 (Window Level)

```swift
panel.level = .floating        // 浮动在普通窗口之上
panel.level = .statusBar       // 状态栏级别（更高）
panel.level = .popUpMenu       // 弹出菜单级别
panel.level = .screenSaver     // 最高级别（谨慎使用）
```

对于这种工具，`.floating` 或 `.statusBar` 是最佳选择。

---

## 2. 窗口焦点管理

### 2.1 显示窗口并获取焦点

```swift
func showPanel() {
    // 1. 设置窗口位置（屏幕中央）
    if let screen = NSScreen.main ?? NSScreen.screens.first {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.midY - panel.frame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // 2. 激活应用并显示窗口（关键步骤）
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    
    // 3. 确保窗口成为key window
    panel.becomeKey()
}
```

### 2.2 激活策略 (Activation Policy)

对于 LSUIElement 后台应用，弹出窗口时需要切换激活策略：

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    func showPanel() {
        // 从 accessory 切换到 regular，显示Dock图标并获取焦点
        NSApp.setActivationPolicy(.regular)
        
        // 延迟一帧确保策略切换完成
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
        }
    }
    
    func hidePanel() {
        panel.orderOut(nil)
        
        // 恢复为 accessory 模式，隐藏Dock图标
        NSApp.setActivationPolicy(.accessory)
    }
}
```

### 2.3 失去焦点自动关闭

通过 NSWindowDelegate 监听焦点变化：

```swift
extension QuickJumpPanelController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // 窗口失去Key状态时自动关闭
        closePanel()
    }
    
    func windowDidResignMain(_ notification: Notification) {
        // 窗口失去Main状态时自动关闭
        closePanel()
    }
}
```

### 2.4 点击外部自动关闭

```swift
class QuickJumpPanelController {
    private var clickMonitor: Any?
    
    func showPanel() {
        panel.makeKeyAndOrderFront(nil)
        
        // 注册全局鼠标点击监控（点击外部关闭）
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
    }
    
    func closePanel() {
        // 移除鼠标监控
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        
        panel.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}
```

### 2.5 焦点管理注意事项

| 方法 | 用途 | 注意 |
|------|------|------|
| `makeKeyAndOrderFront(nil)` | 使窗口成为key窗口并前置 | 必须调用 |
| `NSApp.activate(ignoringOtherApps: true)` | 激活应用 | 对于后台应用必须 |
| `panel.becomeKey()` | 窗口成为key | 通常在makeKeyAndOrderFront后调用 |
| `panel.makeKey()` | 同becomeKey | 较少用 |
| `panel.orderFrontRegardless()` | 强制前置 | 即使应用非活动也前置 |

**重要**: `activate(ignoringOtherApps:)` 是异步的，窗口操作应在下一runloop执行。

---

## 3. 全局快捷键注册

### 三种原生API方案对比

| API | 拦截级别 | 可覆盖系统快捷键 | 沙箱兼容 | 所需权限 | 可消费事件 |
|-----|----------|------------------|----------|----------|------------|
| `RegisterEventHotKey` (Carbon) | 应用级 | ❌ 否 | ✅ 是 | 无 | ✅ 是 |
| `CGEvent.tapCreate` | 硬件级 | ✅ 是 | ❌ 否 | Input Monitoring | ✅ 是 |
| `NSEvent.addGlobalMonitorForEvents` | 系统级 | ✅ 是 | ✅ 是 | Accessibility | ❌ 否 |

### 方案一：RegisterEventHotKey (Carbon) ⭐推荐

**优点**: 沙箱兼容、无需额外权限、可消费事件（应用不触发其他操作）

```swift
import Carbon

// MARK: - 热键数据模型
struct HotKey {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: UInt32
}

// MARK: - Carbon 全局热键管理器
class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var hotKeys: [UInt32: HotKey] = [:]
    
    // 回调函数指针（必须是全局函数）
    private static let eventSpec = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                      eventKind: UInt32(kEventHotKeyPressed))
    ]
    
    var onHotKeyPressed: ((UInt32) -> Void)?
    
    private init() {}
    
    // MARK: - 注册热键
    func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: [ModifierFlag]) -> Bool {
        // 转换modifier flags
        var carbonModifiers: UInt32 = 0
        for modifier in modifiers {
            carbonModifiers |= modifier.carbonFlag
        }
        
        let hotKey = HotKey(id: id, keyCode: keyCode, modifiers: carbonModifiers)
        
        // 创建事件处理器（首次注册时）
        if eventHandler == nil {
            let callback: EventHandlerUPP = { _, eventRef, userData in
                guard let eventRef = eventRef else { return noErr }
                
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                if result == noErr {
                    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData!).takeUnretainedValue()
                    manager.onHotKeyPressed?(hotKeyID.id)
                }
                
                return noErr
            }
            
            var handlerRef: EventHandlerRef?
            let userData = Unmanaged.passUnretained(self).toOpaque()
            
            InstallEventHandler(
                GetEventDispatcherTarget(),
                callback,
                1,
                Self.eventSpec,
                userData,
                &handlerRef
            )
            
            eventHandler = handlerRef
        }
        
        // 注册热键
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            EventHotKeyID(signature: FourCharCode("QJMP"), id: id),
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        
        guard status == noErr, let ref = hotKeyRef else {
            print("注册热键失败: \(status)")
            return false
        }
        
        hotKeyRefs[id] = ref
        hotKeys[id] = hotKey
        
        return true
    }
    
    // MARK: - 注销热键
    func unregisterHotKey(id: UInt32) {
        guard let ref = hotKeyRefs[id] else { return }
        UnregisterEventHotKey(ref)
        hotKeyRefs.removeValue(forKey: id)
        hotKeys.removeValue(forKey: id)
    }
    
    // MARK: - 注销所有热键
    func unregisterAll() {
        hotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        hotKeys.removeAll()
    }
}

// MARK: - 修饰键枚举
enum ModifierFlag {
    case command
    case option
    case control
    case shift
    case capsLock
    
    var carbonFlag: UInt32 {
        switch self {
        case .command:  return UInt32(cmdKey)
        case .option:   return UInt32(optionKey)
        case .control:  return UInt32(controlKey)
        case .shift:    return UInt32(shiftKey)
        case .capsLock: return UInt32(alphaLock)
        }
    }
    
    var nsFlag: NSEvent.ModifierFlags {
        switch self {
        case .command:  return .command
        case .option:   return .option
        case .control:  return .control
        case .shift:    return .shift
        case .capsLock: return .capsLock
        }
    }
}

// MARK: - 常用按键 KeyCode
struct KeyCodes {
    static let kVK_ANSI_1: UInt32 = 18
    static let kVK_ANSI_2: UInt32 = 19
    static let kVK_ANSI_3: UInt32 = 20
    static let kVK_ANSI_4: UInt32 = 21
    static let kVK_ANSI_5: UInt32 = 23
    static let kVK_ANSI_J: UInt32 = 38
    static let kVK_ANSI_K: UInt32 = 40
    static let kVK_Space: UInt32 = 49
    static let kVK_Escape: UInt32 = 53
    static let kVK_Return: UInt32 = 36
    static let kVK_UpArrow: UInt32 = 126
    static let kVK_DownArrow: UInt32 = 125
    static let kVK_F1: UInt32 = 122
    static let kVK_F2: UInt32 = 120
    static let kVK_F3: UInt32 = 99
    static let kVK_F4: UInt32 = 118
    static let kVK_F5: UInt32 = 96
}
```

**使用方式**：

```swift
// 注册 Option+J 作为触发快捷键
GlobalHotkeyManager.shared.registerHotKey(
    id: 1,
    keyCode: KeyCodes.kVK_ANSI_J,
    modifiers: [.option]
)

// 设置回调
GlobalHotkeyManager.shared.onHotKeyPressed = { hotKeyId in
    if hotKeyId == 1 {
        // 显示弹出窗口
        panelController.showPanel()
    }
}
```

### 方案二：CGEventTapCreate（最高权限）

**优点**: 硬件级别拦截，可以覆盖系统快捷键

**缺点**: 需要 Input Monitoring 权限，**不兼容 App Sandbox**

```swift
import CoreGraphics

class CGEventTapHotkeyManager {
    static let shared = CGEventTapHotkeyManager()
    
    private var runLoopSource: CFRunLoopSource?
    private var eventTap: CFMachPort?
    private var isRunning = false
    
    var onKeyEvent: ((CGKeyCode, CGEventFlags, Bool) -> Bool)? // 返回true表示消费事件
    
    private init() {}
    
    // MARK: - 检查权限
    func checkPermission() -> Bool {
        return CGPreflightListenEventAccess()
    }
    
    func requestPermission() -> Bool {
        return CGRequestListenEventAccess()
    }
    
    // MARK: - 启动事件监听
    func startListening() -> Bool {
        guard !isRunning else { return true }
        
        // 检查权限
        guard checkPermission() else {
            print("需要 Input Monitoring 权限")
            _ = requestPermission()
            return false
        }
        
        // 创建事件tap
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            let manager = Unmanaged<CGEventTapHotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
            
            let keyCode = CGEventGetIntegerValueField(event, .keyboardEventKeycode)
            let flags = CGEventGetFlags(event)
            let isKeyDown = (type == .keyDown)
            
            // 调用回调，如果返回true则消费事件
            if let handler = manager.onKeyEvent {
                let consume = handler(UInt32(keyCode), flags, isKeyDown)
                if consume {
                    return Unmanaged.passUnretained(event) // 实际应返回nil消费事件
                    // 注意：Swift中需要特殊处理来返回C NULL
                }
            }
            
            return Unmanaged.passRetained(event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("创建 CGEventTap 失败")
            return false
        }
        
        eventTap = tap
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        self.runLoopSource = runLoopSource
        isRunning = true
        
        return true
    }
    
    // MARK: - 停止监听
    func stopListening() {
        guard isRunning else { return }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }
}
```

### 方案三：NSEvent.addGlobalMonitorForEvents

**优点**: 最简单、沙箱兼容

**缺点**: 不能消费事件（快捷键会同时触发前台应用）

```swift
class NSEventHotkeyManager {
    static let shared = NSEventHotkeyManager()
    private var eventMonitor: Any?
    
    var onShortcutTriggered: (() -> Void)?
    
    private init() {}
    
    // MARK: - 检查 Accessibility 权限
    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    // MARK: - 开始监控
    func startMonitoring(targetKeyCode: UInt16, targetModifiers: NSEvent.ModifierFlags) {
        guard checkAccessibilityPermission() else {
            print("需要 Accessibility 权限")
            return
        }
        
        // 移除已有监控
        stopMonitoring()
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            if event.keyCode == targetKeyCode && modifiers == targetModifiers {
                DispatchQueue.main.async {
                    self.onShortcutTriggered?()
                }
            }
        }
    }
    
    // MARK: - 停止监控
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
```

### 权限要求总结

| API | 所需权限 | Info.plist 配置 |
|-----|----------|----------------|
| RegisterEventHotKey | 无需 | 无 |
| CGEventTap | Input Monitoring | `com.apple.security.temporary-exception.mach-lookup.global-name` |
| NSEvent globalMonitor | Accessibility | 无 |

---

## 4. 键盘事件处理

### 4.1 在窗口内拦截键盘事件

**推荐方式：重写 NSWindow 的 keyDown 方法**

```swift
class QuickJumpWindow: NSWindow {
    var onKeyEvent: ((NSEvent) -> Bool)?  // 返回true表示已处理
    
    override func keyDown(with event: NSEvent) {
        // 回调处理，如果回调返回true则消费事件
        if let handler = onKeyEvent, handler(event) {
            return
        }
        super.keyDown(with: event)
    }
    
    // 拦截数字键1-5、上下箭头、回车、ESC
    static func handleKeyEvent(_ event: NSEvent, 
                                itemCount: Int,
                                selectedIndex: inout Int,
                                onSelect: (Int) -> Void,
                                onCancel: () -> Void) -> Bool {
        switch event.keyCode {
        case KeyCodes.kVK_ANSI_1...KeyCodes.kVK_ANSI_5:
            // 数字键 1-5 直接选择对应项
            let index = Int(event.keyCode) - Int(KeyCodes.kVK_ANSI_1)
            if index < itemCount {
                onSelect(index)
                return true
            }
            
        case KeyCodes.kVK_UpArrow:
            // 上箭头 - 向上选择
            if selectedIndex > 0 {
                selectedIndex -= 1
            } else {
                selectedIndex = itemCount - 1  // 循环到最后一项
            }
            return true
            
        case KeyCodes.kVK_DownArrow:
            // 下箭头 - 向下选择
            if selectedIndex < itemCount - 1 {
                selectedIndex += 1
            } else {
                selectedIndex = 0  // 循环到第一项
            }
            return true
            
        case KeyCodes.kVK_Return:
            // 回车 - 确认选择
            if selectedIndex >= 0 && selectedIndex < itemCount {
                onSelect(selectedIndex)
            }
            return true
            
        case KeyCodes.kVK_Escape:
            // ESC - 取消/关闭
            onCancel()
            return true
            
        default:
            break
        }
        return false
    }
}
```

### 4.2 使用 Local Monitor 作为替代方案

```swift
class KeyboardEventRouter {
    private var localMonitor: Any?
    
    func startListening(handler: @escaping (NSEvent) -> NSEvent?) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // handler返回nil表示消费事件，返回event表示传递
            return handler(event)
        }
    }
    
    func stopListening() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
```

### 4.3 KeyCode 参考表

| 按键 | KeyCode | 说明 |
|------|---------|------|
| 0-9 | 29, 18-23, 25, 26 | 数字键 |
| A-Z | 0-14, 15-17, 31, 35, 37-40 | 字母键 |
| 空格 | 49 | Space |
| 回车 | 36 | Return |
| ESC | 53 | Escape |
| 上箭头 | 126 | Up Arrow |
| 下箭头 | 125 | Down Arrow |
| 左箭头 | 123 | Left Arrow |
| 右箭头 | 124 | Right Arrow |
| F1-F12 | 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111 | 功能键 |
| Delete | 51 | Backspace |
| Tab | 48 | Tab |

---

## 5. UI设计建议

### 5.1 使用 NSVisualEffectView 实现毛玻璃效果

```swift
class QuickJumpContentView: NSView {
    private let visualEffectView: NSVisualEffectView
    private let tableView: NSTableView
    private let scrollView: NSScrollView
    
    override init(frame frameRect: NSRect) {
        // 创建毛玻璃效果视图
        visualEffectView = NSVisualEffectView()
        visualEffectView.material = .menu           // 菜单材质
        visualEffectView.blendingMode = .behindWindow // 窗口后方混合
        visualEffectView.state = .active            // 始终激活效果
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12   // 圆角
        visualEffectView.layer?.masksToBounds = true
        
        // 创建表格视图
        tableView = NSTableView()
        tableView.headerView = nil                  // 隐藏表头
        tableView.selectionHighlightStyle = .none   // 自定义选中样式
        tableView.backgroundColor = .clear          // 透明背景
        tableView.rowHeight = 44                    // 行高
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        
        // 添加列
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        column.title = "Path"
        column.width = 480
        column.minWidth = 480
        tableView.addTableColumn(column)
        
        // 创建滚动视图
        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        
        super.init(frame: frameRect)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // 使用 Autolayout
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(visualEffectView)
        visualEffectView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            scrollView.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -8)
        ])
    }
}
```

### 5.2 自定义选中高亮样式

```swift
class DirectoryCellView: NSTableCellView {
    private let indexLabel: NSTextField
    private let pathLabel: NSTextField
    private let iconView: NSImageView
    private var highlightView: NSView?
    
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateAppearance()
        }
    }
    
    private func updateAppearance() {
        switch backgroundStyle {
        case .emphasized:
            // 选中状态 - 使用强调色背景
            indexLabel.textColor = .white
            pathLabel.textColor = .white
            
        default:
            // 普通状态
            indexLabel.textColor = .secondaryLabelColor
            pathLabel.textColor = .labelColor
        }
    }
    
    // 设置行数据
    func configure(index: Int, path: String, isSelected: Bool) {
        indexLabel.stringValue = "\(index + 1)"
        pathLabel.stringValue = path
        
        // 设置快捷键提示 (1-5)
        if index < 5 {
            indexLabel.stringValue = "\(index + 1)"
        }
    }
}
```

### 5.3 窗口位置计算

```swift
enum WindowPosition {
    case screenCenter
    case mouseCursor
    case menuBarCenter
    
    func calculateFrame(for windowSize: NSSize) -> NSRect {
        switch self {
        case .screenCenter:
            guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                return NSRect(origin: .zero, size: windowSize)
            }
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.midX - windowSize.width / 2
            let y = visibleFrame.midY - windowSize.height / 2
            return NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height)
            
        case .mouseCursor:
            let mouseLocation = NSEvent.mouseLocation
            let x = mouseLocation.x - windowSize.width / 2
            let y = mouseLocation.y - windowSize.height - 10  // 鼠标上方10像素
            return NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height)
            
        case .menuBarCenter:
            guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                return NSRect(origin: .zero, size: windowSize)
            }
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.midX - windowSize.width / 2
            let y = visibleFrame.maxY - windowSize.height - 8  // 距离菜单栏8像素
            return NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height)
        }
    }
}
```

---

## 6. 完整项目代码示例

### 6.1 项目结构

```
QuickJump/
├── App/
│   ├── AppDelegate.swift
│   └── main.swift
├── Core/
│   ├── GlobalHotkeyManager.swift
│   ├── DirectoryStore.swift
│   └── WindowPosition.swift
├── UI/
│   ├── QuickJumpPanel.swift
│   ├── QuickJumpPanelController.swift
│   ├── QuickJumpContentView.swift
│   └── DirectoryCellView.swift
└── Resources/
    └── Info.plist
```

### 6.2 AppDelegate.swift

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var panelController: QuickJumpPanelController!
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. 配置为后台应用（无Dock图标）
        NSApp.setActivationPolicy(.accessory)
        
        // 2. 创建状态栏图标
        setupStatusItem()
        
        // 3. 初始化面板控制器
        panelController = QuickJumpPanelController()
        
        // 4. 注册全局快捷键 (Option + J)
        setupGlobalHotkey()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "QuickJump")
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 QuickJump", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "偏好设置...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    private func setupGlobalHotkey() {
        let success = GlobalHotkeyManager.shared.registerHotKey(
            id: 1,
            keyCode: KeyCodes.kVK_ANSI_J,
            modifiers: [.option]
        )
        
        if success {
            GlobalHotkeyManager.shared.onHotKeyPressed = { [weak self] hotKeyId in
                if hotKeyId == 1 {
                    self?.togglePanel()
                }
            }
            print("全局快捷键 Option+J 注册成功")
        } else {
            print("全局快捷键注册失败")
        }
    }
    
    @objc func showPanel() {
        panelController.showPanel()
    }
    
    @objc func togglePanel() {
        if panelController.isVisible {
            panelController.closePanel()
        } else {
            panelController.showPanel()
        }
    }
    
    @objc func openPreferences() {
        // 打开偏好设置窗口
    }
    
    @objc func quit() {
        GlobalHotkeyManager.shared.unregisterAll()
        NSApplication.shared.terminate(nil)
    }
}
```

### 6.3 QuickJumpPanel.swift

```swift
import Cocoa
import SwiftUI

class QuickJumpPanel: NSPanel {
    
    init() {
        let contentView = QuickJumpHostingView()
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // 核心配置
        self.isFloatingPanel = true
        self.level = .floating
        self.becomesKeyOnlyIfNeeded = false
        self.hidesOnDeactivate = true
        self.isReleasedWhenClosed = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.shadow?.shadowOffset = NSSize(width: 0, height: -8)
        self.shadow?.shadowBlurRadius = 20
        self.animationBehavior = .utilityWindow
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // 设置内容视图
        self.contentView = contentView
        
        // 圆角
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 12
        self.contentView?.layer?.masksToBounds = true
    }
}

// MARK: - SwiftUI 托管视图
class QuickJumpHostingView: NSView {
    private var hostingView: NSHostingView<QuickJumpView>!
    
    init() {
        super.init(frame: .zero)
        
        let viewModel = QuickJumpViewModel()
        hostingView = NSHostingView(rootView: QuickJumpView(viewModel: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

### 6.4 QuickJumpPanelController.swift

```swift
import Cocoa

class QuickJumpPanelController: NSWindowDelegate {
    
    private let panel: QuickJumpPanel
    private var clickMonitor: Any?
    private var selectedIndex: Int = 0
    private var directoryStore: DirectoryStore
    
    var isVisible: Bool {
        return panel.isVisible
    }
    
    init() {
        panel = QuickJumpPanel()
        directoryStore = DirectoryStore()
        panel.delegate = self
        setupKeyHandling()
    }
    
    // MARK: - 显示面板
    func showPanel() {
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        
        // 1. 更新最近目录列表
        directoryStore.refreshRecentDirectories()
        
        // 2. 计算位置（屏幕中央偏上）
        positionPanel()
        
        // 3. 切换激活策略（从后台应用到前台）
        NSApp.setActivationPolicy(.regular)
        
        // 4. 延迟一帧确保策略切换完成
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.becomeKey()
            
            // 5. 注册外部点击监控
            self.setupClickMonitor()
        }
    }
    
    // MARK: - 关闭面板
    func closePanel() {
        // 移除点击监控
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        
        // 动画关闭
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
            
            // 恢复为后台应用
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    // MARK: - 定位面板
    private func positionPanel() {
        let position = WindowPosition.screenCenter
        let frame = position.calculateFrame(for: NSSize(width: 520, height: 300))
        panel.setFrame(frame, display: false)
    }
    
    // MARK: - 点击外部监控
    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // 检查点击位置是否在面板外
            guard let self = self else { return }
            let mouseLoc = NSEvent.mouseLocation
            if !NSPointInRect(mouseLoc, self.panel.frame) {
                self.closePanel()
            }
        }
    }
    
    // MARK: - 键盘事件处理
    private func setupKeyHandling() {
        panel.onKeyEvent = { [weak self] event -> Bool in
            guard let self = self else { return false }
            
            let itemCount = self.directoryStore.recentDirectories.count
            
            return QuickJumpWindow.handleKeyEvent(
                event,
                itemCount: min(itemCount, 5),
                selectedIndex: &self.selectedIndex,
                onSelect: { index in
                    self.jumpToDirectory(at: index)
                },
                onCancel: {
                    self.closePanel()
                }
            )
        }
    }
    
    // MARK: - 跳转到目录
    private func jumpToDirectory(at index: Int) {
        guard index < directoryStore.recentDirectories.count else { return }
        
        let path = directoryStore.recentDirectories[index]
        print("跳转到: \(path)")
        
        // 这里可以实现：
        // 1. 通过 AppleScript 激活 Finder 并跳转
        // 2. 通过 NSWorkspace 打开目录
        // 3. 通过 Accessibility API 操作终端
        
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        
        closePanel()
    }
    
    // MARK: - NSWindowDelegate
    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }
    
    func windowWillClose(_ notification: Notification) {
        closePanel()
    }
}
```

### 6.5 QuickJumpView.swift (SwiftUI)

```swift
import SwiftUI

// MARK: - 数据模型
class QuickJumpViewModel: ObservableObject {
    @Published var directories: [DirectoryItem] = []
    @Published var selectedIndex: Int = 0
    
    init() {
        loadMockData()
    }
    
    private func loadMockData() {
        directories = [
            DirectoryItem(name: "Documents", path: "/Users/alice/Documents", icon: "doc.text"),
            DirectoryItem(name: "Projects", path: "/Users/alice/Projects", icon: "folder"),
            DirectoryItem(name: "Downloads", path: "/Users/alice/Downloads", icon: "arrow.down.circle"),
            DirectoryItem(name: "Desktop", path: "/Users/alice/Desktop", icon: "desktopcomputer"),
            DirectoryItem(name: "Home", path: "/Users/alice", icon: "house")
        ]
    }
}

struct DirectoryItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let icon: String
}

// MARK: - SwiftUI 视图
struct QuickJumpView: View {
    @ObservedObject var viewModel: QuickJumpViewModel
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索目录...", text: $searchText)
                    .textFieldStyle(.plain)
                    
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Divider()
                .padding(.horizontal, 12)
                .padding(.top, 8)
            
            // 目录列表
            List(Array(viewModel.directories.enumerated()), id: \.element.id) { index, item in
                DirectoryRowView(
                    index: index,
                    item: item,
                    isSelected: index == viewModel.selectedIndex
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(
                    index == viewModel.selectedIndex
                        ? Color.accentColor.opacity(0.8)
                        : Color.clear
                )
            }
            .listStyle(.plain)
            .frame(height: CGFloat(min(viewModel.directories.count, 5)) * 48 + 8)
            
            // 底部提示
            HStack {
                HStack(spacing: 4) {
                    KeyBadge(text: "1-5")
                    Text("选择")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    KeyBadge(text: "↑↓")
                    Text("切换")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    KeyBadge(text: "↩")
                    Text("确认")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    KeyBadge(text: "esc")
                    Text("关闭")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 500)
    }
}

// MARK: - 目录行视图
struct DirectoryRowView: View {
    let index: Int
    let item: DirectoryItem
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // 序号/快捷键
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                )
            
            // 图标
            Image(systemName: item.icon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .white : .accentColor)
                .frame(width: 24)
            
            // 名称和路径
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Text(item.path)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Color.white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - 快捷键提示徽章
struct KeyBadge: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
            )
    }
}
```

### 6.6 DirectoryStore.swift

```swift
import Foundation

class DirectoryStore {
    @Published private(set) var recentDirectories: [String] = []
    
    private let userDefaultsKey = "recentDirectories"
    private let maxCount = 5
    
    init() {
        loadDirectories()
    }
    
    func refreshRecentDirectories() {
        loadDirectories()
        
        // 如果没有数据，使用模拟数据
        if recentDirectories.isEmpty {
            recentDirectories = [
                NSHomeDirectory() + "/Documents",
                NSHomeDirectory() + "/Projects",
                NSHomeDirectory() + "/Downloads",
                NSHomeDirectory() + "/Desktop",
                NSHomeDirectory()
            ]
        }
    }
    
    func addDirectory(_ path: String) {
        // 移除已存在的相同路径
        recentDirectories.removeAll { $0 == path }
        
        // 添加到开头
        recentDirectories.insert(path, at: 0)
        
        // 限制数量
        if recentDirectories.count > maxCount {
            recentDirectories = Array(recentDirectories.prefix(maxCount))
        }
        
        saveDirectories()
    }
    
    private func loadDirectories() {
        if let saved = UserDefaults.standard.stringArray(forKey: userDefaultsKey) {
            recentDirectories = saved
        }
    }
    
    private func saveDirectories() {
        UserDefaults.standard.set(recentDirectories, forKey: userDefaultsKey)
    }
}
```

### 6.7 Info.plist 配置

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    
    <!-- 关键配置：后台应用，无Dock图标 -->
    <key>LSUIElement</key>
    <true/>
    
    <!-- 后台启动 -->
    <key>LSBackgroundOnly</key>
    <false/>
    
    <!-- 高分辨率支持 -->
    <key>NSHighResolutionCapable</key>
    <true/>
    
    <!-- 辅助功能权限说明 -->
    <key>NSAccessibilityUsageDescription</key>
    <string>QuickJump 需要辅助功能权限来监听全局键盘快捷键。</string>
    
    <!-- 主storyboard（如果不使用storyboard需删除） -->
    <key>NSMainStoryboardFile</key>
    <string></string>
    
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

### 6.8 main.swift（不使用 Storyboard 时）

```swift
import Cocoa

// 创建应用和委托
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// 启动应用
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
```

---

## 7. 方案对比和推荐组合

### 7.1 全局快捷键方案选择决策树

```
是否需要上架 Mac App Store?
├── ✅ 是 → 使用 RegisterEventHotKey (Carbon)
│          沙箱兼容，无需额外权限
└── ❌ 否 → 是否需要覆盖系统快捷键?
            ├── ✅ 是 → 使用 CGEventTap
            │          硬件级拦截，可覆盖系统快捷键
            │          需要 Input Monitoring 权限
            └── ❌ 否 → 使用 RegisterEventHotKey (Carbon)
                       最稳定、最简单、无权限需求
```

### 7.2 推荐组合（快速目录跳转工具）

| 组件 | 推荐方案 | 理由 |
|------|----------|------|
| **窗口类型** | NSPanel + borderless + fullSizeContentView | 专为辅助窗口设计，无边框最符合工具风格 |
| **窗口效果** | NSVisualEffectView + .menu 材质 | 毛玻璃效果，与系统风格一致 |
| **全局快捷键** | RegisterEventHotKey (Carbon) | 无需权限，沙箱兼容，最稳定 |
| **快捷键组合** | Option + J | 避免与系统快捷键冲突 |
| **键盘处理** | 重写 NSWindow.keyDown | 最可靠，完全控制 |
| **焦点管理** | activate + makeKeyAndOrderFront + becomeKey | 确保焦点立即到位 |
| **自动关闭** | windowDidResignKey + 点击外部监控 | 双重保障 |
| **应用类型** | LSUIElement (后台应用) | 无Dock图标，通过快捷键触发 |
| **UI框架** | SwiftUI + NSHostingView | 开发效率高，效果精美 |

### 7.3 响应速度优化建议

1. **预创建窗口**: 应用启动时创建 NSPanel，但不显示，避免首次弹出的创建开销
2. **延迟加载**: 目录列表在显示前更新，但UI框架提前准备好
3. **缓存最近目录**: 使用 UserDefaults 缓存最近目录，避免频繁磁盘访问
4. **异步激活**: `setActivationPolicy` 和 `activate` 在主线程但使用异步延迟确保执行顺序
5. **轻量级动画**: 使用 `animationBehavior = .utilityWindow` 或自定义快速淡入动画

### 7.4 关键注意事项

1. **setActivationPolicy 延迟**: 从 `.accessory` 切换到 `.regular` 不是立即生效的，需要在下一个 runloop 执行窗口显示
2. **Carbon 回调限制**: `RegisterEventHotKey` 的回调是C函数指针，不能捕获Swift闭包上下文，需通过 `userInfo` 传参
3. **Input Monitoring vs Accessibility**: 不同API需要不同权限，UI提示要清晰说明
4. **沙箱限制**: 如果计划上架 App Store，必须使用 RegisterEventHotKey，不能使用 CGEventTap
5. **窗口释放**: `isReleasedWhenClosed = false` 避免窗口关闭后被释放，保证可重复使用
6. **多屏幕支持**: 使用 `NSScreen.main` 获取当前屏幕，处理多显示器场景

---

## 附录：KeyCode 完整参考

```swift
// 完整 KeyCode 定义 (Carbon HIToolbox/HIServices)
struct KeyCodes {
    // 字母键 A-Z
    static let kVK_ANSI_A: UInt32 = 0x00
    static let kVK_ANSI_S: UInt32 = 0x01
    static let kVK_ANSI_D: UInt32 = 0x02
    static let kVK_ANSI_F: UInt32 = 0x03
    static let kVK_ANSI_H: UInt32 = 0x04
    static let kVK_ANSI_G: UInt32 = 0x05
    static let kVK_ANSI_Z: UInt32 = 0x06
    static let kVK_ANSI_X: UInt32 = 0x07
    static let kVK_ANSI_C: UInt32 = 0x08
    static let kVK_ANSI_V: UInt32 = 0x09
    static let kVK_ANSI_B: UInt32 = 0x0B
    static let kVK_ANSI_Q: UInt32 = 0x0C
    static let kVK_ANSI_W: UInt32 = 0x0D
    static let kVK_ANSI_E: UInt32 = 0x0E
    static let kVK_ANSI_R: UInt32 = 0x0F
    static let kVK_ANSI_Y: UInt32 = 0x10
    static let kVK_ANSI_T: UInt32 = 0x11
    static let kVK_ANSI_1: UInt32 = 0x12
    static let kVK_ANSI_2: UInt32 = 0x13
    static let kVK_ANSI_3: UInt32 = 0x14
    static let kVK_ANSI_4: UInt32 = 0x15
    static let kVK_ANSI_6: UInt32 = 0x16
    static let kVK_ANSI_5: UInt32 = 0x17
    static let kVK_ANSI_Equal: UInt32 = 0x18
    static let kVK_ANSI_9: UInt32 = 0x19
    static let kVK_ANSI_7: UInt32 = 0x1A
    static let kVK_ANSI_Minus: UInt32 = 0x1B
    static let kVK_ANSI_8: UInt32 = 0x1C
    static let kVK_ANSI_0: UInt32 = 0x1D
    static let kVK_ANSI_O: UInt32 = 0x1F
    static let kVK_ANSI_U: UInt32 = 0x20
    static let kVK_ANSI_I: UInt32 = 0x22
    static let kVK_ANSI_P: UInt32 = 0x23
    static let kVK_ANSI_L: UInt32 = 0x25
    static let kVK_ANSI_J: UInt32 = 0x26
    static let kVK_ANSI_K: UInt32 = 0x28
    static let kVK_ANSI_N: UInt32 = 0x2D
    static let kVK_ANSI_M: UInt32 = 0x2E
    
    // 特殊键
    static let kVK_Return: UInt32 = 0x24
    static let kVK_Tab: UInt32 = 0x30
    static let kVK_Space: UInt32 = 0x31
    static let kVK_Delete: UInt32 = 0x33
    static let kVK_Escape: UInt32 = 0x35
    static let kVK_Command: UInt32 = 0x37
    static let kVK_Shift: UInt32 = 0x38
    static let kVK_CapsLock: UInt32 = 0x39
    static let kVK_Option: UInt32 = 0x3A
    static let kVK_Control: UInt32 = 0x3B
    static let kVK_RightCommand: UInt32 = 0x36
    static let kVK_RightOption: UInt32 = 0x3D
    static let kVK_Function: UInt32 = 0x3F
    static let kVK_Home: UInt32 = 0x73
    static let kVK_PageUp: UInt32 = 0x74
    static let kVK_ForwardDelete: UInt32 = 0x75
    static let kVK_End: UInt32 = 0x77
    static let kVK_PageDown: UInt32 = 0x79
    
    // 方向键
    static let kVK_LeftArrow: UInt32 = 0x7B
    static let kVK_RightArrow: UInt32 = 0x7C
    static let kVK_DownArrow: UInt32 = 0x7D
    static let kVK_UpArrow: UInt32 = 0x7E
    
    // F1-F12
    static let kVK_F1: UInt32 = 0x7A
    static let kVK_F2: UInt32 = 0x78
    static let kVK_F3: UInt32 = 0x63
    static let kVK_F4: UInt32 = 0x76
    static let kVK_F5: UInt32 = 0x60
    static let kVK_F6: UInt32 = 0x61
    static let kVK_F7: UInt32 = 0x62
    static let kVK_F8: UInt32 = 0x64
    static let kVK_F9: UInt32 = 0x65
    static let kVK_F10: UInt32 = 0x6D
    static let kVK_F11: UInt32 = 0x67
    static let kVK_F12: UInt32 = 0x6F
}
```

---

*报告生成时间: 2025年*
*适用于 macOS 12.0+ (Monterey), Swift 5.9+, Xcode 15+*
