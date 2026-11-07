import Cocoa

/// Standard responder-chain actions enable editing shortcuts in WebKit and Cocoa fields.
enum ApplicationMenu {
    static func install() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "QuickKeyJump")
        appMenu.addItem(withTitle: L("退出 QuickKeyJump", "Quit QuickKeyJump"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("编辑", "Edit"))
        editMenu.addItem(withTitle: L("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        for (title, action, key) in [
            (L("剪切", "Cut"), "cut:", "x"),
            (L("复制", "Copy"), "copy:", "c"),
            (L("粘贴", "Paste"), "paste:", "v"),
            (L("全选", "Select All"), "selectAll:", "a")
        ] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
}
