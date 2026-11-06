import AppKit

/// Reads window targets without activating Finder, opening a window or navigating it.
enum FinderWindowFolderSampler {
    static func sample(at date: Date) -> [RecentFolder] {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty else { return [] }
        let script = """
        if application "Finder" is not running then return ""
        tell application "Finder"
            set folderURLs to {}
            repeat with finderWindow in (get Finder windows)
                try
                    set end of folderURLs to (URL of (target of finderWindow))
                end try
            end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return folderURLs as text
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let output = Pipe(), errors = Pipe()
        task.standardOutput = output
        task.standardError = errors
        do { try task.run() }
        catch { report("FINDER_WINDOWS launch_failed \(error.localizedDescription)"); return [] }
        let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3, execute: timeout)
        // Drain stdout before waiting, so a large result cannot fill the pipe and block.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        timeout.cancel()
        guard task.terminationStatus == 0 else {
            report("FINDER_WINDOWS failed status=\(task.terminationStatus) error=\(String(data: errorData, encoding: .utf8) ?? "")")
            return []
        }
        let folders = RecentFolderSampling.finderFolders(from: String(data: data, encoding: .utf8) ?? "", sampledAt: date) { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }
        report("FINDER_WINDOWS sampled count=\(folders.count)")
        return folders
    }

    private static func report(_ message: String) {
        DispatchQueue.main.async { DiagnosticLogger.shared.log(message) }
    }
}
