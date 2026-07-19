import Cocoa
import Carbon

final class ShortcutRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onRecord: ((UInt16, UInt) -> Void)?
    var onCancel: (() -> Void)?
    private var eventMonitor: Any?

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 110),
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

        let cancelBtn = NSButton(title: "取消", target: self, action: #selector(doCancel))
        cancelBtn.bezelStyle = .recessed
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        guard let cv = contentView else { return }
        cv.addSubview(prompt)
        cv.addSubview(hint)
        cv.addSubview(cancelBtn)
        NSLayoutConstraint.activate([
            prompt.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            prompt.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
            hint.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            hint.topAnchor.constraint(equalTo: prompt.bottomAnchor, constant: 6),
            cancelBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
        ])
    }

    /// 启动录制：显示面板并安装本地事件监听器
    func beginRecording() {
        center()
        orderFrontRegardless()
        makeKey()

        // 本地事件监听器确保我们的 app 内键盘事件不会被其他窗口抢走
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
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

    private func handleKey(_ event: NSEvent) {
        let keyCode = event.keyCode
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let clean = mods.intersection(allowed)

        if keyCode == UInt16(kVK_Escape) {
            doCancel()
            return
        }
        guard clean.rawValue != 0 else { return }

        cleanup()
        onRecord?(keyCode, UInt(clean.rawValue))
        super.close()
    }
}
