import Cocoa
import Carbon
import Combine

/// Restores a shared default when an application becomes active.
/// Input-source changes within the active application are deliberately left alone.
final class InputSourceManager: ObservableObject {
    static let shared = InputSourceManager()

    struct Source: Identifiable {
        let id: String
        let name: String
        fileprivate let inputSource: TISInputSource
    }

    @Published private(set) var sources: [Source] = []
    @Published private(set) var selectionFailed = false
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "QKJDefaultInputSourceEnabled")
            scheduleApplication()
        }
    }
    @Published var selectedID: String {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "QKJDefaultInputSourceID")
            scheduleApplication()
        }
    }

    var selectedSourceUnavailable: Bool {
        !selectedID.isEmpty && !sources.contains { $0.id == selectedID }
    }

    private var activationObserver: NSObjectProtocol?
    private var sourcesObserver: NSObjectProtocol?
    private var pendingApplication: DispatchWorkItem?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "QKJDefaultInputSourceEnabled")
        selectedID = UserDefaults.standard.string(forKey: "QKJDefaultInputSourceID") ?? ""
    }

    func start() {
        guard activationObserver == nil else { return }
        refreshSources()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleApplication()
        }
        sourcesObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshSources()
        }
        scheduleApplication()
    }

    func refreshSources() {
        let filters: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ]
        let list = TISCreateInputSourceList(filters as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
        sources = list.compactMap { source in
            guard let id = stringProperty(source, kTISPropertyInputSourceID),
                  let name = stringProperty(source, kTISPropertyLocalizedName) else { return nil }
            return Source(id: id, name: name, inputSource: source)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func scheduleApplication() {
        pendingApplication?.cancel()
        pendingApplication = nil
        selectionFailed = false
        guard isEnabled, !selectedID.isEmpty,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        // Let macOS finish restoring the newly active application's input source first.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let source = self.sources.first(where: { $0.id == self.selectedID }) else { return }
            self.selectionFailed = TISSelectInputSource(source.inputSource) != noErr
        }
        pendingApplication = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    deinit {
        pendingApplication?.cancel()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let sourcesObserver {
            DistributedNotificationCenter.default().removeObserver(sourcesObserver)
        }
    }
}
