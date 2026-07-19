import Cocoa
import SwiftUI

final class WindowManagementPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private var selectedIndex = 0
    var onAction: ((WindowAction) -> Void)?
    var onCancel: (() -> Void)?
    private let actions = WindowAction.allCases

    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: CGFloat(52 * WindowAction.allCases.count + 72)),
                  styleMask: [.titled, .fullSizeContentView],
                  backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        titlebarAppearsTransparent = true
        title = ""
        isReleasedWhenClosed = false
        setupUI()
    }

    private func setupUI() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        cv.layer?.cornerRadius = 12

        let hostView = NSHostingView(rootView: WindowManagementRows(
            actions: actions,
            selectedIndex: selectedIndex,
            onTap: { [weak self] in self?.dispatch($0) }
        ))
        hostView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(hostView)
        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: cv.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            hostView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        ])
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 18, 19, 20, 21, 23, 22: // 1-6
            let idx = [18, 19, 20, 21, 23, 22].firstIndex(of: Int(event.keyCode))!
            if idx < actions.count { dispatch(actions[idx]) }
        case 126: selectedIndex = max(0, selectedIndex - 1); refresh()
        case 125: selectedIndex = min(actions.count - 1, selectedIndex + 1); refresh()
        case 36: dispatch(actions[selectedIndex])
        case 53: onCancel?(); close()
        default: super.keyDown(with: event)
        }
    }

    private func refresh() {
        guard let cv = contentView else { return }
        cv.subviews.compactMap { $0 as? NSHostingView<WindowManagementRows> }.first?.rootView = WindowManagementRows(
            actions: actions, selectedIndex: selectedIndex,
            onTap: { [weak self] in self?.dispatch($0) }
        )
    }

    private func dispatch(_ action: WindowAction) {
        onAction?(action)
        close()
    }
}

private struct WindowManagementRows: View {
    let actions: [WindowAction]
    let selectedIndex: Int
    let onTap: (WindowAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("窗口管理")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)

            VStack(spacing: 2) {
                ForEach(Array(actions.enumerated()), id: \.element.rawValue) { idx, action in
                    WindowActionRowView(action: action, isSelected: idx == selectedIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { onTap(action) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)

            Divider().padding(.horizontal, 12)

            HStack(spacing: 0) {
                Text("1-6 选择  ·  ↵ 确认  ·  Esc 取消")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(height: 28)
        }
        .frame(width: 320)
    }
}

private struct WindowActionRowView: View {
    let action: WindowAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(action.shortcut)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.12))
                )
                .foregroundColor(isSelected ? .white : .secondary)

            Image(systemName: action.icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 24)

            Text(action.displayName)
                .font(.system(size: 14, weight: .medium))

            Spacer()

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.6)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .foregroundColor(isSelected ? .white : .primary)
    }
}
