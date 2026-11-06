import SwiftUI

// Keep the property wrapper unambiguous on SDKs that also expose a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

typealias RecorderCocoa = KeyboardShortcuts.RecorderCocoa

struct SettingsView: View {
    @AppStorage("AppLanguage") private var language = "zh"
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    @ViewState private var autoLaunch = LaunchManager.isEnabled
    @ObservedObject private var inputSources = InputSourceManager.shared
    @ObservedObject private var ignoreList = IgnoreListManager.shared

    var body: some View {
        VStack(spacing: 0) {
            headerView
            settingsListView
            footerView
        }
        .frame(width: 480)
        .id(language) // force refresh on language change
        .background(
            VisualEffectView(material: .windowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("偏好设置", "Preferences"))
                    .font(.system(size: 16, weight: .bold))
                Text(L("自定义全局快捷键", "Customize global shortcuts"))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            languagePicker
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
    }

    private var languagePicker: some View {
        Picker("", selection: $language) {
            Text("中文").tag("zh")
            Text("English").tag("en")
        }
        .pickerStyle(.segmented)
        .frame(width: 120)
        .onChange(of: language) { _, v in
            AppLanguage.current = AppLanguage(rawValue: v) ?? .zh
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    private var settingsListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(ActionType.allCases, id: \.rawValue) { action in
                    ShortcutRowView(action: action)
                        .padding(.horizontal, 16)
                    if action != ActionType.allCases.last {
                        Divider().padding(.leading, 60).padding(.trailing, 16)
                    }
                }
                Divider().padding(.vertical, 6)
                inputSourceSettingsView
                Divider().padding(.vertical, 6)
                ignoreListView
            }
            .padding(.vertical, 4)
        }
    }

    private var inputSourceSettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("自动恢复默认输入法", "Restore Default Input Source"), isOn: $inputSources.isEnabled)
                .font(.system(size: 13, weight: .semibold))
                .toggleStyle(.switch)
                .controlSize(.small)
            Text(L("每次切换 App 时恢复默认输入法；当前 App 内仍可手动切换。", "Restore on app activation. Manual switching within the active app remains available."))
                .font(.system(size: 11)).foregroundColor(.secondary)
            Picker(L("默认输入法", "Default Input Source"), selection: $inputSources.selectedID) {
                Text(L("请选择输入法", "Choose an input source")).tag("")
                ForEach(inputSources.sources) { source in
                    Text(source.name).tag(source.id)
                }
                if inputSources.selectedSourceUnavailable {
                    Text(L("已保存的输入法不可用", "Saved input source unavailable"))
                        .tag(inputSources.selectedID)
                }
            }
            .font(.system(size: 12))
            if inputSources.selectedSourceUnavailable {
                Text(L("该输入法已被禁用或移除，请重新选择。", "This input source is disabled or removed. Please choose another."))
                    .font(.system(size: 11)).foregroundColor(.orange)
            } else if inputSources.isEnabled && inputSources.selectedID.isEmpty {
                Text(L("选择输入法后开始生效。", "Choose an input source to activate this feature."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            if inputSources.selectionFailed {
                Text(L("系统未能切换输入法，请检查该输入法是否可用。", "The system could not switch input sources. Check that the source is available."))
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .onAppear { inputSources.refreshSources() }
    }

    /// 忽视清单栏目：清单内的目录及其子目录不出现在快速跳转候选里
    private var ignoreListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("忽视清单", "Ignore List"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L("清单内的目录及其子目录不会出现在快速跳转候选中", "Folders in this list and their subfolders are excluded from Quick Jump"))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: pickFolderToIgnore) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 10))
                        Text(L("添加目录…", "Add Folder…")).font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain).foregroundColor(.accentColor)
            }
            .padding(.horizontal, 20)

            if ignoreList.paths.isEmpty {
                Text(L("暂无忽视目录", "No ignored folders"))
                    .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 20).padding(.vertical, 4)
            } else {
                ForEach(Array(ignoreList.paths.enumerated()), id: \.element) { index, path in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.minus")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 12)).lineLimit(1)
                            Text(path)
                                .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(action: { ignoreList.remove(at: index) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("移除", "Remove"))
                    }
                    .padding(.horizontal, 20).padding(.vertical, 4)
                    if index != ignoreList.paths.count - 1 {
                        Divider().padding(.leading, 20).padding(.trailing, 20)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// 弹出目录选择面板，选择要加入忽视清单的目录
    private func pickFolderToIgnore() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L("选择要忽视的目录（含其子目录）", "Choose a folder to ignore (including its subfolders)")
        panel.prompt = L("添加", "Add")
        if panel.runModal() == .OK, let url = panel.url {
            ignoreList.add(url.path)
        }
    }

    private var footerView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button(action: {
                    for a in ActionType.allCases { KeyboardShortcuts.reset(a.name) }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 9))
                        Text(L("恢复默认", "Reset Defaults")).font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain).foregroundColor(.secondary)

                Spacer()

                Toggle(isOn: $autoLaunch) {
                    Text(L("开机自启", "Launch at Login")).font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: autoLaunch) { _, v in
                    v ? LaunchManager.enable() : LaunchManager.disable()
                }

                Button(action: {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "hand.raised.fill").font(.system(size: 9))
                        Text(L("辅助功能权限…", "Accessibility…")).font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Text("v\(appVersion)").font(.system(size: 9)).foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

private struct ShortcutRowView: View {
    let action: ActionType

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture {
                    NotificationCenter.default.post(
                        name: .triggerAction, object: nil,
                        userInfo: ["action": action]
                    )
                }
                .help(L("点击触发 ", "Click to trigger ") + action.displayName)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName).font(.system(size: 13, weight: .medium))
                Text(action.description).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            RecorderView(name: action.name)
        }
        .padding(.horizontal, 4).padding(.vertical, 6)
    }
}

private struct RecorderView: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    func makeNSView(context: Context) -> RecorderCocoa { RecorderCocoa(for: name) }
    func updateNSView(_ v: RecorderCocoa, context: Context) {}
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blendingMode; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
