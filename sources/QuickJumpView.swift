import SwiftUI

// MARK: - 快速跳转主视图

/// 快速跳转主视图
/// 显示 5 个最近使用的目录，支持键盘上下选择、数字键快速跳转
/// 整体风格参考 macOS Spotlight，简洁紧凑
struct QuickJumpView: View {

    // MARK: - 输入属性

    /// 最近文件夹数据管理器（由核心模块提供）
    @ObservedObject var folderManager: RecentFolderManager

    /// 用户确认选择后的回调
    let onSelect: (RecentFolder) -> Void

    /// 用户取消/关闭后的回调
    let onCancel: () -> Void

    // MARK: - 状态

    /// 当前选中项的索引（0-4）
    @State private var selectedIndex: Int = 0

    // MARK: - 常量

    /// 视图尺寸常量
    private enum Layout {
        /// 窗口宽度
        static let windowWidth: CGFloat = 500
        /// 单行高度
        static let rowHeight: CGFloat = 52
        /// 行与行之间的间距
        static let rowSpacing: CGFloat = 2
        /// 列表区域内边距
        static let listPadding: CGFloat = 8
        /// 圆角半径
        static let cornerRadius: CGFloat = 12
        /// 快捷键标签尺寸
        static let shortcutSize: CGFloat = 22
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerView

            // 文件夹列表
            folderListView

            Divider()
                .padding(.horizontal, 12)
                .opacity(0.4)

            // 底部键盘提示
            footerView
        }
        .frame(width: Layout.windowWidth)
        .background(Color.clear)
        // 当数据变化时，限制选中索引在有效范围内
        .onChange(of: folderManager.folders.count) { _, _ in
            clampSelection()
        }
        // 监听来自 KeyboardHandler 的键盘事件通知
        .onReceive(NotificationCenter.default.publisher(for: .quickJumpMoveSelection)) { notification in
            if let direction = notification.userInfo?["direction"] as? Int {
                if direction < 0 {
                    moveUp()
                } else {
                    moveDown()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickJumpConfirmSelection)) { _ in
            confirmSelection()
        }
    }

    // MARK: - 子视图

    /// 顶部标题视图
    private var headerView: some View {
        HStack {
            Text("最近使用的文件夹")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// 文件夹列表视图
    private var folderListView: some View {
        VStack(spacing: Layout.rowSpacing) {
            // 只显示前 5 个项目
            ForEach(Array(folderManager.folders.prefix(5).enumerated()), id: \.element.id) { index, folder in
                FolderRowView(
                    folder: folder,
                    isSelected: index == selectedIndex,
                    shortcut: folder.shortcut
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    // 鼠标点击直接选择并确认
                    selectAndConfirm(index: index)
                }
            }
        }
        .padding(.horizontal, Layout.listPadding)
        .padding(.vertical, 4)
    }

    /// 底部提示栏视图
    private var footerView: some View {
        HStack(spacing: 4) {
            // 提示文字使用小字体，灰色
            Text("↑↓ 选择")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text("·")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.horizontal, 4)

            Text("↵ 确认")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text("·")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.horizontal, 4)

            Text("⌘1-5 快速跳转")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text("·")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.horizontal, 4)

            Text("Esc 取消")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 公开操作（供外部调用）

    /// 向上移动选择（循环到末尾）
    func moveUp() {
        let count = folderManager.folders.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    /// 向下移动选择（循环到开头）
    func moveDown() {
        let count = folderManager.folders.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    /// 选择指定索引并立即确认跳转
    func selectIndex(_ index: Int) {
        let count = folderManager.folders.count
        guard index >= 0, index < count else { return }
        selectedIndex = index
        confirmSelection()
    }

    /// 确认当前选择项，触发跳转回调
    func confirmSelection() {
        let count = folderManager.folders.count
        guard selectedIndex >= 0, selectedIndex < count else {
            // 没有有效选择时直接关闭
            onCancel()
            return
        }
        let folder = folderManager.folders[selectedIndex]
        onSelect(folder)
    }

    /// 取消操作，关闭窗口
    func cancel() {
        onCancel()
    }

    // MARK: - 私有方法

    /// 选择并确认（用于鼠标点击）
    private func selectAndConfirm(index: Int) {
        selectIndex(index)
    }

    /// 限制选中索引在有效数据范围内
    private func clampSelection() {
        let count = folderManager.folders.count
        if count == 0 {
            selectedIndex = 0
        } else if selectedIndex >= count {
            selectedIndex = count - 1
        }
    }
}

// MARK: - 文件夹行视图

/// 单个文件夹列表项视图
/// 显示快捷键标签、文件夹名称和路径
private struct FolderRowView: View {

    /// 文件夹数据
    let folder: RecentFolder

    /// 是否处于选中状态
    let isSelected: Bool

    /// 快捷键数字文本
    let shortcut: String

    var body: some View {
        HStack(spacing: 12) {
            // 快捷键数字标签
            shortcutBadge

            // 文件夹名称和路径
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(folder.path)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .opacity(isSelected ? 0.8 : 0.5)
            }

            Spacer()

            // 选中状态时显示进入指示箭头
            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.7)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        // 选中状态使用强调色背景 + 白色文字，未选中使用透明背景
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .foregroundColor(isSelected ? .white : .primary)
    }

    /// 快捷键数字徽章
    private var shortcutBadge: some View {
        Text(shortcut)
            .font(.system(size: 12, weight: .bold))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
            )
            .foregroundColor(isSelected ? .white : .secondary)
    }
}

// MARK: - 预览支持

#if DEBUG

/// 预览用的模拟数据管理器
private class PreviewFolderManager: RecentFolderManager {
    override init() {
        super.init()
        self.folders = [
            RecentFolder(name: "Documents", path: "/Users/alice/Documents", shortcut: "1"),
            RecentFolder(name: "Projects", path: "/Users/alice/Workspace/Projects", shortcut: "2"),
            RecentFolder(name: "Downloads", path: "/Users/alice/Downloads", shortcut: "3"),
            RecentFolder(name: "Desktop", path: "/Users/alice/Desktop", shortcut: "4"),
            RecentFolder(name: "dotfiles", path: "/Users/alice/Workspace/dotfiles", shortcut: "5"),
        ]
    }
}

struct QuickJumpView_Previews: PreviewProvider {
    static var previews: some View {
        QuickJumpView(
            folderManager: PreviewFolderManager(),
            onSelect: { _ in },
            onCancel: { }
        )
        .frame(width: 500)
        .background(.regularMaterial)
    }
}
#endif
