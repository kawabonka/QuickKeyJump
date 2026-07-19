import Cocoa
import Carbon

/// 快捷键录制面板 — NSPanel 子类，按下任意组合键后回调
final class ShortcutRecorderPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onRecord: ((UInt16, UInt) -> Void)?
    var onCancel: (() -> Void)?

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .modalPanel
        titlebarAppearsTransparent = true
        title = ""
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        let prompt = NSTextField(labelWithString: "按下新快捷键...")
        prompt.font = .systemFont(ofSize: 14, weight: .medium)
        prompt.alignment = .center
        prompt.translatesAutoresizingMaskIntoConstraints = false

        let subtext = NSTextField(labelWithString: "包含至少一个修饰键（⌘⌥⌃⇧）+ 字母/符号键")
        subtext.font = .systemFont(ofSize: 10)
        subtext.textColor = .secondaryLabelColor
        subtext.alignment = .center
        subtext.translatesAutoresizingMaskIntoConstraints = false

        let cancelBtn = NSButton(title: "取消", target: self, action: #selector(handleCancel))
        cancelBtn.bezelStyle = .recessed
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = contentView else { return }
        contentView.addSubview(prompt)
        contentView.addSubview(subtext)
        contentView.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            prompt.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            prompt.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            subtext.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            subtext.topAnchor.constraint(equalTo: prompt.bottomAnchor, constant: 6),
            cancelBtn.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cancelBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    @objc private func handleCancel() {
        onCancel?()
        close()
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // 只接受修饰键（自交后取有效键）
        let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let cleanMods = mods.intersection(allowed)

        if keyCode == UInt16(kVK_Escape) {
            handleCancel()
            return
        }

        // 必须有至少一个修饰键
        guard cleanMods.rawValue != 0 else {
            super.keyDown(with: event)
            return
        }

        onRecord?(keyCode, UInt(cleanMods.rawValue))
        close()
    }

    override func cancelOperation(_ sender: Any?) {
        handleCancel()
    }
}
