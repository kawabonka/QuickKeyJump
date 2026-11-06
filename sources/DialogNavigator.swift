import Cocoa
import ApplicationServices

/// Captures the actual focused window before Quick Jump takes keyboard focus.
/// The AX window may belong to a file-picker helper rather than the host app.
final class DialogNavigator {
    struct Target {
        let host: NSRunningApplication
        let window: AXUIElement
        let focusedControl: AXUIElement?
    }

    private static var isNavigating = false
    private static let logger = DiagnosticLogger.shared

    static func checkPermission() -> Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func captureTarget(host: NSRunningApplication) -> Target? {
        logger.snapshot("capture_target", host: host, tree: true)
        guard checkPermission() else { logger.log("CAPTURE_FAILED accessibility_denied"); return nil }
        let system = AXUIElementCreateSystemWide()
        let focused = element(system, kAXFocusedUIElementAttribute)
        let focusedApp = element(system, kAXFocusedApplicationAttribute)
        // Prefer the focused control's window: a picker can be hosted by a helper process.
        guard let window = focused.flatMap({ element($0, kAXWindowAttribute) })
                ?? focusedApp.flatMap({ element($0, kAXFocusedWindowAttribute) }) else { return nil }
        logger.log("TARGET_CAPTURED \(logger.describe(window))")
        return Target(host: host, window: window, focusedControl: focused)
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
        // Raise the saved window, rather than an arbitrary window of the host app.
        let raised = AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        logger.log("AX_RAISE result=\(raised.rawValue)")
        let mainStatus = AXUIElementSetAttributeValue(target.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        logger.log("AX_SET main result=\(mainStatus.rawValue)")
        let windowFocusStatus = AXUIElementSetAttributeValue(target.window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        logger.log("AX_SET windowFocus result=\(windowFocusStatus.rawValue)")
        if let control = target.focusedControl {
            let controlFocusStatus = AXUIElementSetAttributeValue(control, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            logger.log("AX_SET controlFocus result=\(controlFocusStatus.rawValue)")
        }

        waitUntil(timeout: 1.5, condition: { isTargetFocused(target) }) { ready in
            logger.log("FOCUS_READY ready=\(ready)")
            logger.snapshot("focus_wait_end", targetWindow: target.window, host: target.host)
            guard ready else {
                finish(L("无法恢复文件选择窗口的焦点，已停止跳转。请点击文件选择框后重试。", "Could not restore focus to the file picker. Click it and try again."))
                return
            }
            // Existing search/name fields must never be mistaken for Go to Folder.
            let existingFields = descendants(target.window).filter { isTextField($0) }
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
                        let nodes = descendants(target.window)
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
        guard let focused = focusedElement() else { return false }
        // Sheets can be represented either as children or as focused windows.
        var current: AXUIElement? = focused
        for _ in 0..<30 {
            guard let node = current else { break }
            if CFEqual(node, target.window) { return true }
            current = element(node, kAXParentAttribute)
        }
        if let window = element(focused, kAXWindowAttribute), CFEqual(window, target.window) { return true }
        let system = AXUIElementCreateSystemWide()
        guard let app = element(system, kAXFocusedApplicationAttribute),
              let window = element(app, kAXFocusedWindowAttribute) else { return false }
        return CFEqual(window, target.window)
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
