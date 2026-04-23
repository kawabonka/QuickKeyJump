# macOS Quick Folder Jump - 开发计划

## 目标
实现类似 Windows Listary Ctrl+G 的快速目录跳转工具，纯原生代码，无需安装依赖。

## 阶段划分

### Stage 1 — 技术调研（并行）
需要调研明确以下关键技术点：

**调研A: 最近使用目录的数据源**
- `com.apple.finder.plist` 中 `FXRecentFolders` 的结构（已有Python参考）
- 是否有更优的Cocoa API获取（NSDocumentController.shared.recentDocumentURLs 等）
- NSURL.bookmarkData解析（最近位置可能是bookmark格式）
- 备选: 通过Spotlight (mdfind) 或NSMetadataQuery获取

**调研B: 快速UI窗口实现**
- NSPanel（NSWindow）无边框、快速弹出方案
- 窗口焦点窃取（makeKeyAndOrderFront）
- 全局快捷键注册（NSEvent.addGlobalMonitorForEventsMatchingMask）
- 数字键1-5、上下箭头、回车的键盘事件处理
- 窗口自动关闭（失去焦点时）

**调研C: 保存对话框跳转方案**
- Accessibility API（AX API）获取当前焦点窗口和对话框元素
- 识别NSOpenPanel/NSSavePanel（通过AXRole判断）
- 向对话框发送按键/设置路径的技术方案：
  - 方案1: 通过AX API设置AXValue（直接设置目录URL）
  - 方案2: 模拟Cmd+Shift+G，然后输入路径回车
  - 方案3: 通过AppleScript tell对话框设置
- 图片中展示的"最近访问的位置"下拉菜单，是否可通过NSPopupButton的AX API直接操作

**调研D: Finder跳转方案**
- Finder导航：通过Finder的Scripting Bridge或AppleScript
- 通过NSWorkspace打开文件夹
- 通过Scripting Bridge直接控制Finder窗口的target

### Stage 2 — 原型实现
基于调研结果，实现完整功能的Swift原生应用：

1. **AppDelegate** - 应用生命周期、全局快捷键注册
2. **JumpPanel** - 自定义无边框窗口，显示最近目录列表
3. **RecentFolderManager** - 读取和缓存最近使用目录
4. **DialogNavigator** - 保存对话框跳转逻辑
5. **FinderNavigator** - Finder跳转逻辑
6. **KeyboardHandler** - 键盘事件处理（1-5、箭头、回车、ESC）

### Stage 3 — 测试与Debug
- 编译和运行说明
- Debug方法（日志输出、Accessibility Inspector等）
- 常见问题排查

## 交付物
1. 完整Swift项目（.swift文件）
2. 使用说明
3. Debug指南
4. Raycast集成方式（可选）
