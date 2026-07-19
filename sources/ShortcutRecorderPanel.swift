import Cocoa
import Carbon

/// 快捷键录制面板 — 通过 flagsChanged + keyDown 双事件流可靠捕捉组合键
final class ShortcutRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onRecord: ((UInt16, UInt) -> Void)?
    var onCancel: (() -> Void)?
    private var eventMonitor: Any?
    private var currentModifiers: UInt = 0

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 130),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .modalPanel
        titlebarAppearsTransparent = true
        title = ""
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        setupUI()
    }

    private func setupUI() {
        let prompt = NSTextField(labelWithString: "按下新快捷键...")
        prompt.font = .systemFont(ofSize: 15, weight: .medium)
        prompt.alignment = .center
        prompt.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "⌘ ⌥ ⌃ ⇧ + 任意键，Esc 取消")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        // 实时显示当前摁下的修饰键
        let modLabel = NSTextField(labelWithString: "")
        modLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        modLabel.alignment = .center
        modLabel.textColor = .controlAccentColor
        modLabel.translatesAutoresizingMaskIntoConstraints = false
        modLabel.tag = 999 // 用于后续更新

        let cancelBtn = NSButton(title: "取消", target: self, action: #selector(doCancel))
        cancelBtn.bezelStyle = .recessed
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        guard let cv = contentView else { return }
        cv.addSubview(prompt)
        cv.addSubview(hint)
        cv.addSubview(modLabel)
        cv.addSubview(cancelBtn)
        NSLayoutConstraint.activate([
            prompt.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            prompt.topAnchor.constraint(equalTo: cv.topAnchor, constant: 18),
            hint.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            hint.topAnchor.constraint(equalTo: prompt.bottomAnchor, constant: 4),
            modLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            modLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
            cancelBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
        ])
    }

    /// 启动录制：显示面板、激活 app、安装双事件流监听
    func beginRecording() {
        currentModifiers = 0
        center()
        orderFrontRegardless()
        makeKey()
        NSApp.activate(ignoringOtherApps: true)

        // 同时监听 keyDown 和 flagsChanged
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            guard let self = self else { return event }

            switch event.type {
            case .flagsChanged:
                // 修饰键变化：更新当前状态 + UI 反馈
                let raw = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                self.currentModifiers = UInt(raw.intersection(allowed).rawValue)
                self.updateModifierLabel()
                return nil

            case .keyDown:
                if event.keyCode == UInt16(kVK_Escape) {
                    self.doCancel()
                    return nil
                }
                // 必须至少按住一个修饰键
                guard self.currentModifiers != 0 else { return nil }
                self.cleanup()
                self.onRecord?(event.keyCode, self.currentModifiers)
                self.close()
                return nil

            default:
                return event
            }
        }

        // 延迟再激活一次，确保焦点不会被刚失去焦点的前窗口抢回去
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateModifierLabel() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let cv = self.contentView,
                  let label = cv.viewWithTag(999) as? NSTextField else { return }
            var parts: [String] = []
            if self.currentModifiers & UInt(controlKey) != 0 { parts.append("⌃") }
            if self.currentModifiers & UInt(optionKey)  != 0 { parts.append("⌥") }
            if self.currentModifiers & UInt(shiftKey)   != 0 { parts.append("⇧") }
            if self.currentModifiers & UInt(cmdKey)      != 0 { parts.append("⌘") }
            label.stringValue = parts.isEmpty ? "" : parts.joined()
        }
    }

    private func cleanup() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    override func close() {
        cleanup()
        super.close()
    }

    @objc private func doCancel() {
        cleanup()
        onCancel?()
        super.close()
    }

    /// 兜底 keyDown：如果窗口是 key window 但没有 event monitor 匹配到
    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            doCancel()
            return
        }
        guard currentModifiers != 0 else {
            super.keyDown(with: event)
            return
        }
        cleanup()
        onRecord?(event.keyCode, currentModifiers)
        close()
    }
}
