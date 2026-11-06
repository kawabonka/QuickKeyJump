import Cocoa
import ApplicationServices
import Combine

/// Opt-in, local diagnostic sessions. Never records text-field values or keystrokes.
final class DiagnosticLogger: ObservableObject {
    static let shared = DiagnosticLogger()
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "QKJDiagnosticLoggingEnabled")
            if isEnabled { startSession() }
            else { append("SESSION_STOP") }
        }
    }
    @Published private(set) var lastError: String?
    @Published private(set) var sessionURL: URL?
    let directory: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.quickkeyjump.diagnostics")
    private var attemptID = "-"

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/QuickKeyJump", isDirectory: true)
        isEnabled = defaults.bool(forKey: "QKJDiagnosticLoggingEnabled")
        if isEnabled { startSession() }
    }

    private func startSession() {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        sessionURL = directory.appendingPathComponent("QuickKeyJump-\(stamp.string(from: Date()))-\(UUID().uuidString.prefix(8)).log")
        lastError = nil
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "test"
        append("SESSION_START version=\(version) os=\(ProcessInfo.processInfo.operatingSystemVersionString) pid=\(ProcessInfo.processInfo.processIdentifier) AXTrusted=\(AXIsProcessTrusted())")
    }

    func beginAttempt() {
        guard isEnabled else { return }
        attemptID = String(UUID().uuidString.prefix(8))
        log("QUICK_JUMP_INVOKED")
    }

    func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        append(message())
    }

    private func append(_ message: String) {
        guard let url = sessionURL else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "\(formatter.string(from: Date())) [\(attemptID)] \(message)\n"
        queue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try Data().write(to: url)
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } catch {
                DispatchQueue.main.async { self?.lastError = error.localizedDescription }
            }
        }
    }

    func openFolder() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                DispatchQueue.main.async { NSWorkspace.shared.open(self.directory) }
            } catch {
                DispatchQueue.main.async { self.lastError = error.localizedDescription }
            }
        }
    }

    /// Used by the smoke check to await queued writes; never used during navigation.
    func flush() { queue.sync {} }

    func snapshot(_ stage: String, targetWindow: AXUIElement? = nil, host: NSRunningApplication? = nil, tree: Bool = false) {
        guard isEnabled else { return }
        let system = AXUIElementCreateSystemWide()
        let front = NSWorkspace.shared.frontmostApplication
        log("SNAPSHOT \(stage) front=\(front?.bundleIdentifier ?? "nil") pid=\(front?.processIdentifier ?? 0) AXTrusted=\(AXIsProcessTrusted()) modifiers=\(NSEvent.modifierFlags.rawValue)")
        let app = readElement(system, kAXFocusedApplicationAttribute)
        let control = readElement(system, kAXFocusedUIElementAttribute)
        log("focusedApp \(describe(app))")
        if let app { log("focusedAppWindow \(describe(readElement(app, kAXFocusedWindowAttribute)))") }
        log("focusedControl \(describe(control))")
        if let control { log("controlWindow \(describe(readElement(control, kAXWindowAttribute)))") }
        if let targetWindow { log("savedWindow \(describe(targetWindow))") }
        var pids = Set<pid_t>()
        if let host { pids.insert(host.processIdentifier) }
        for node in [app, control, targetWindow].compactMap({ $0 }) {
            var pid: pid_t = 0
            AXUIElementGetPid(node, &pid)
            if pid > 0 { pids.insert(pid) }
        }
        for pid in pids.sorted() {
            let process = AXUIElementCreateApplication(pid)
            let windows = read(process, kAXWindowsAttribute) as? [AXUIElement] ?? []
            log("process pid=\(pid) bundle=\(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "nil") windows=\(windows.count)")
            for window in windows.prefix(8) {
                log("window \(describe(window))")
                if tree { dumpTree(window) }
            }
        }
        if tree, let targetWindow { dumpTree(targetWindow) }
    }

    func describe(_ node: AXUIElement?) -> String {
        guard let node else { return "nil" }
        var pid: pid_t = 0
        let pidStatus = AXUIElementGetPid(node, &pid)
        let role = read(node, kAXRoleAttribute) as? String ?? "?"
        let subrole = read(node, kAXSubroleAttribute) as? String ?? "-"
        let identifier = read(node, "AXIdentifier") as? String ?? "-"
        // Window titles help identify separate Go to Folder windows. No field contents.
        let title = role == kAXWindowRole || role == kAXSheetRole ? read(node, kAXTitleAttribute) as? String ?? "" : ""
        return "id=\(CFHash(node)) pid=\(pid) pidStatus=\(pidStatus.rawValue) role=\(role) subrole=\(subrole) identifier=\(String(reflecting: identifier)) title=\(String(reflecting: title))"
    }

    private func read(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(node, key as CFString, &result)
        // Only log failures for the key focus/window queries, not every optional property.
        if status != .success && [kAXFocusedApplicationAttribute, kAXFocusedUIElementAttribute, kAXFocusedWindowAttribute, kAXWindowsAttribute].contains(key) {
            log("AX_READ_FAILED key=\(key) status=\(status.rawValue) node=\(CFHash(node))")
        }
        return status == .success ? result : nil
    }

    private func readElement(_ node: AXUIElement, _ key: String) -> AXUIElement? {
        guard let result = read(node, key), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private func dumpTree(_ root: AXUIElement) {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var seen = Set<CFHashCode>()
        var index = 0
        var truncated = false
        while index < queue.count && seen.count < 100 {
            let (node, depth) = queue[index]; index += 1
            guard seen.insert(CFHash(node)).inserted else { continue }
            log("TREE depth=\(depth) \(describe(node))")
            guard depth < 5 else {
                for key in ["AXSheets", kAXChildrenAttribute] {
                    if let children = read(node, key) as? [AXUIElement], !children.isEmpty { truncated = true }
                }
                continue
            }
            for key in ["AXSheets", kAXChildrenAttribute] {
                if let children = read(node, key) as? [AXUIElement] {
                    if children.count > 40 { truncated = true }
                    queue.append(contentsOf: children.prefix(40).map { ($0, depth + 1) })
                }
            }
        }
        log("TREE_END nodes=\(seen.count) truncated=\(truncated || index < queue.count)")
    }
}
