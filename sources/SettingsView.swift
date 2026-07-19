import SwiftUI
import Carbon

/// 快捷键设置视图 — 每个操作的快捷键行
struct ShortcutRowView: View {
    let action: ActionType
    @ObservedObject var settings: SettingsManager
    @State private var isRecording = false
    var onShortcutChanged: () -> Void

    private var currentShortcut: Shortcut {
        settings.shortcut(for: action)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(action.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 快捷键录制按钮
            shortcutButton
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var shortcutButton: some View {
        Button(action: { isRecording = true }) {
            Text(isRecording ? "录制中..." : currentShortcut.displayString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        
        .onChange(of: isRecording) { _, recording in
            if recording {
                showRecorder()
            }
        }
    }

    private func showRecorder() {
        let panel = ShortcutRecorderPanel()
        panel.onRecord = { keyCode, modifiers in
            let shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers)
            settings.setShortcut(shortcut, for: action)
            DispatchQueue.main.async {
                isRecording = false
                onShortcutChanged()
            }
        }
        panel.onCancel = {
            DispatchQueue.main.async {
                isRecording = false
            }
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        // 激活应用使其获得键盘焦点
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 偏好设置主视图
struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    var onShortcutChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题区域
            headerView

            // 快捷键列表
            shortcutListView

            Divider()
                .padding(.horizontal, 16)

            // 底部操作区和版本号
            footerView
        }
        .frame(width: 480)
        .background(
            VisualEffectView(material: .windowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    // MARK: Subviews

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("偏好设置")
                    .font(.system(size: 16, weight: .bold))
                Text("自定义全局快捷键")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var shortcutListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(ActionType.allCases, id: \.rawValue) { action in
                    ShortcutRowView(
                        action: action,
                        settings: settings,
                        onShortcutChanged: onShortcutChanged
                    )
                    .padding(.horizontal, 16)

                    if action != ActionType.allCases.last {
                        Divider()
                            .padding(.leading, 60)
                            .padding(.trailing, 16)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 240)
    }

    private var footerView: some View {
        HStack {
            // 恢复默认按钮
            Button(action: {
                settings.resetAllToDefaults()
                onShortcutChanged()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                    Text("恢复默认")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("将所有快捷键恢复为默认设置")

            Spacer()

            // 版本号
            Text("v\(appVersion) (\(buildVersion))")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// 用于 SwiftUI 中显示原生 NSVisualEffectView 的包装
private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: SettingsManager.shared, onShortcutChanged: {})
    }
}
#endif
