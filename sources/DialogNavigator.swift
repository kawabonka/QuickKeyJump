import Cocoa
import ApplicationServices

/// Captures the actual focused window before Quick Jump takes keyboard focus.
/// The AX window may belong to a file-picker helper rather than the host app.
final class DialogNavigator {
    struct Target {
        let host: NSRunningApplication
        let window: AXUIElement
        let picker: AXUIElement
    }

    private static var isNavigating = false
    private static let logger = DiagnosticLogger.shared

    static func checkPermission() -> Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func captureTarget(host: NSRunningApplication) -> Target? {
        guard checkPermission() else { logger.log("CAPTURE_FAILED accessibility_denied"); return nil }
        let app = AXUIElementCreateApplication(host.processIdentifier)
        let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let focusedWindow = element(app, kAXFocusedWindowAttribute)
        let candidates = windows.compactMap { window -> (window: AXUIElement, picker: AXUIElement)? in
            guard let picker = findPicker(in: window) else { return nil }
            return (window, picker)
        }
        let choice = FilePickerResolver.choose(candidates: candidates, focusedWindow: focusedWindow,
                                               same: { CFEqual($0, $1) })
        logger.log("PICKER_CANDIDATES count=\(candidates.count)")
        for candidate in candidates {
            logger.log("PICKER_CANDIDATE window=\(logger.describe(candidate.window)) picker=\(logger.describe(candidate.picker))")
        }
        guard let choice else {
            logger.log("CAPTURE_FAILED no_unique_file_picker")
            logger.snapshot("capture_failed", host: host, tree: true)
            return nil
        }
        logger.log("TARGET_CAPTURED window=\(logger.describe(choice.window)) picker=\(logger.describe(choice.picker))")
        return Target(host: host, window: choice.window, picker: choice.picker)
    }

    static func navigate(to path: String, target: Target?, completion: @escaping (String?) -> Void) {
        logger.snapshot("navigation_start", targetWindow: target?.window, host: target?.host)
        guard !isNavigating else {
            completion(L("上一次跳转尚未完成，请稍后再试。", "A navigation is already in progress. Please try again shortly."))
            return
        }
        guard checkPermission() else {
            requestPermission()
            completion(L("请在系统设置中授予 QuickKeyJump 辅助功能权限。", "Grant QuickKeyJump Accessibility permission in System Settings."))
            return
        }
        guard let target else {
            completion(L("未能记录原来的文件选择窗口。请点击文件选择框后重试。", "Could not capture the original file picker. Click it and try again."))
            return
        }
        let expandedPath = (path as NSString).expandingTildeInPath
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &directory), directory.boolValue else {
            completion(L("目标文件夹不存在或无法访问。", "The target folder does not exist or is inaccessible."))
            return
        }
        isNavigating = true
        let finish: (String?) -> Void = { error in
            logger.log("NAVIGATION_END result=\(error ?? "go_dialog_dismissed")")
            if error != nil { logger.snapshot("failure_before_alert", targetWindow: target.window, host: target.host, tree: true) }
            isNavigating = false
            completion(error)
        }
        let activated = target.host.activate(options: [])
        logger.log("ACTIVATE_HOST result=\(activated)")
        let raised = AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        logger.log("AX_RAISE result=\(raised.rawValue)")
        let mainStatus = AXUIElementSetAttributeValue(target.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        logger.log("AX_SET main result=\(mainStatus.rawValue)")
        // Reacquire the picker and its controls; web controls saved before activation
        // can already be invalid (the 4.6.1 log returned AXError -25202).
        var lastFocusAttempt = Date.distantPast
        waitUntil(timeout: 1.5, condition: {
            if isTargetFocused(target) { return true }
            if Date().timeIntervalSince(lastFocusAttempt) >= 0.25 {
                lastFocusAttempt = Date()
                restorePickerFocus(target)
            }
            return isTargetFocused(target)
        }) { ready in
            logger.log("FOCUS_READY ready=\(ready)")
            logger.snapshot("focus_wait_end", targetWindow: target.window, host: target.host)
            guard ready else {
                finish(L("无法恢复文件选择窗口的焦点，已停止跳转。请点击文件选择框后重试。", "Could not restore focus to the file picker. Click it and try again."))
                return
            }
            // Existing search/name fields must never be mistaken for Go to Folder.
            guard let picker = findPicker(in: target.window) else {
                finish(L("文件选择框已关闭或不可访问，请重新打开后重试。", "The file picker closed or is inaccessible. Reopen it and try again.")); return
            }
            let existingFields = descendants(picker).filter { isTextField($0) }
            logger.log("BASELINE_FIELDS count=\(existingFields.count)")
            for field in existingFields { logger.log("BASELINE_FIELD \(logger.describe(field))") }
            if let error = sendKeys("key code 5 using {command down, shift down}") {
                finish(error); return
            }
            logger.snapshot("after_cmd_shift_g", targetWindow: target.window, host: target.host)
            var lastObservation = ""
            var pathField: AXUIElement?
            waitUntil(timeout: 2, condition: {
                let targetFocused = isTargetFocused(target)
                let focused = focusedElement()
                let wasExisting = focused.map { candidate in existingFields.contains(where: { CFEqual($0, candidate) }) } ?? false
                if logger.isEnabled {
                    let observation = "targetFocused=\(targetFocused) existingField=\(wasExisting) control=\(logger.describe(focused))"
                    if observation != lastObservation { logger.log("PATH_FIELD_POLL \(observation)"); lastObservation = observation }
                }
                guard targetFocused, let focused, isTextField(focused), !wasExisting else { return false }
                pathField = focused
                return true
            }) { opened in
                logger.log("PATH_FIELD_DETECTED opened=\(opened)")
                guard opened, let field = pathField else {
                    finish(L("未检测到“前往文件夹”输入框，已停止操作，没有粘贴或发送回车。", "Go to Folder did not open. No text or Return was sent."))
                    return
                }
                guard isTargetFocused(target), let focused = focusedElement(), CFEqual(focused, field) else {
                    finish(L("输入焦点已改变，已停止跳转。", "Keyboard focus changed. Navigation stopped.")); return
                }
                let writeStatus = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, expandedPath as CFString)
                logger.log("SET_PATH result=\(writeStatus.rawValue)")
                guard writeStatus == .success else {
                    finish(L("无法填写“前往文件夹”路径。", "Could not fill the Go to Folder path.")); return
                }
                // Wait for the picker to process the path before confirming it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard isTargetFocused(target), let focused = focusedElement(), CFEqual(focused, field),
                          string(field, kAXValueAttribute) == expandedPath else {
                        finish(L("路径输入未完成或焦点已改变，已停止跳转。", "Path entry did not complete or focus changed. Navigation stopped.")); return
                    }
                    if let error = sendKeys("key code 36") { finish(error); return }
                    waitUntil(timeout: 2, condition: {
                        // Disappearance confirms the path was accepted, not merely that keys were sent.
                        let nodes = findPicker(in: target.window).map { descendants($0) } ?? []
                        return isTargetFocused(target) && nodes.count > 1
                            && !nodes.contains(where: { CFEqual($0, field) })
                    }) { accepted in
                        finish(accepted ? nil : L("路径已填写，但文件选择框尚未确认跳转，请检查窗口。", "The path was entered, but navigation could not be confirmed. Check the picker."))
                    }
                }
            }
        }
    }

    private static func sendKeys(_ commands: String) -> String? {
        logger.log("SEND_KEYS command=\(commands)")
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"System Events\"\n\(commands)\nend tell")?.executeAndReturnError(&error)
        guard let error else { logger.log("SEND_KEYS script_returned_without_error"); return nil }
        logger.log("SEND_KEYS_ERROR \(error)")
        print("[DialogNavigator] \(error)")
        return L("发送快捷键失败。请检查系统设置 → 隐私与安全性 → 自动化中 QuickKeyJump 对 System Events 的权限。", "Could not send keys. Check QuickKeyJump's System Events permission under System Settings → Privacy & Security → Automation.")
    }

    private static func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() { completion(true) }
            else if Date() >= deadline { completion(false) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll) }
        }
        poll()
    }

    private static func isTargetFocused(_ target: Target) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.host.processIdentifier,
              let picker = findPicker(in: target.window), let focused = focusedElement() else { return false }
        // The host window alone is insufficient: the focus must be inside its picker.
        return FilePickerResolver.contains(focused, root: picker,
                                           parent: { element($0, kAXParentAttribute) },
                                           same: { CFEqual($0, $1) })
            || descendants(picker).contains(where: { CFEqual($0, focused) })
    }

    private static func restorePickerFocus(_ target: Target) {
        guard let picker = findPicker(in: target.window) else {
            logger.log("RESTORE_PICKER missing_or_invalid"); return
        }
        let windowRaised = AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        logger.log("RESTORE_PICKER_WINDOW result=\(windowRaised.rawValue)")
        let raised = AXUIElementPerformAction(picker, kAXRaiseAction as CFString)
        logger.log("RAISE_PICKER result=\(raised.rawValue)")
        let nodes = descendants(picker)
        // Focus a fresh file-list control, never the stale web text area or Open button.
        let controls = nodes.filter { string($0, kAXRoleAttribute) == kAXBrowserRole }
            + nodes.filter { string($0, kAXRoleAttribute) == kAXOutlineRole }
            + nodes.filter { string($0, kAXSubroleAttribute) == kAXSearchFieldSubrole }
        for control in controls {
            let status = AXUIElementSetAttributeValue(control, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            logger.log("RESTORE_PICKER result=\(status.rawValue) control=\(logger.describe(control))")
            if isTargetFocused(target) { return }
        }
        logger.log("RESTORE_PICKER no_control_restored_focus")
    }

    private static func findPicker(in window: AXUIElement) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited: [AXUIElement] = []
        var index = 0
        while index < queue.count && visited.count < 160 {
            let (node, depth) = queue[index]; index += 1
            guard !visited.contains(where: { CFEqual($0, node) }) else { continue }
            visited.append(node)
            let identifier = string(node, "AXIdentifier")
            if identifier == "open-panel" || identifier == "save-panel" { return node }
            // Some native panels omit their panel identifier. Require file-picker
            // controls instead of treating every modal dialog as a file picker.
            let role = string(node, kAXRoleAttribute)
            if role == kAXSheetRole || role == kAXWindowRole {
                let controls = children(node).flatMap { [$0] + children($0) }
                let identifiers = Set(controls.compactMap { string($0, "AXIdentifier") })
                if identifiers.contains("where popup") && identifiers.contains("OKButton")
                    && identifiers.contains("CancelButton") { return node }
            }
            if depth < 6 { queue.append(contentsOf: children(node).map { ($0, depth + 1) }) }
        }
        return nil
    }

    private static func children(_ node: AXUIElement) -> [AXUIElement] {
        // Sheets first: a file list can contain thousands of unrelated children.
        (value(node, "AXSheets") as? [AXUIElement] ?? [])
            + (value(node, kAXChildrenAttribute) as? [AXUIElement] ?? [])
    }

    private static func focusedElement() -> AXUIElement? {
        element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
    }

    private static func isTextField(_ node: AXUIElement) -> Bool {
        let role = string(node, kAXRoleAttribute)
        return role == kAXTextFieldRole || role == kAXComboBoxRole
    }

    private static func string(_ node: AXUIElement, _ key: String) -> String? {
        value(node, key) as? String
    }

    private static func value(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, key as CFString, &result) == .success else { return nil }
        return result
    }

    private static func element(_ node: AXUIElement, _ key: String) -> AXUIElement? {
        guard let result = value(node, key), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func descendants(_ root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue = [root]
        var index = 0
        while index < queue.count && result.count < 1500 {
            let node = queue[index]; index += 1
            guard !result.contains(where: { CFEqual($0, node) }) else { continue }
            result.append(node)
            for key in [kAXChildrenAttribute, "AXSheets"] {
                if let children = value(node, key) as? [AXUIElement] { queue.append(contentsOf: children) }
            }
        }
        return result
    }
}
