// Run: xcrun swiftc -module-cache-path /tmp/swift-module-cache sources/FilePickerResolver.swift tests/FilePickerResolverTests.swift -o /tmp/qkj-picker-tests && /tmp/qkj-picker-tests
@main
struct FilePickerResolverTests {
    static func main() {
        // Regression fixture: IDs from the two failed attempts in the 4.6.1 log.
        let webWindow = 1668256320
        let chatWindow = 1668253440
        let openPanel = 1685032928
        let candidates = [(window: chatWindow, picker: openPanel)]
        let resolved = FilePickerResolver.choose(candidates: candidates, focusedWindow: webWindow, same: ==)
        precondition(resolved?.window == chatWindow && resolved?.picker == openPanel,
                     "The focused web window must not override the window containing open-panel")
        let other = (window: 90, picker: 91)
        precondition(FilePickerResolver.choose(candidates: candidates + [other], focusedWindow: webWindow, same: ==) == nil,
                     "Do not guess between multiple pickers when focus does not identify either")
        precondition(FilePickerResolver.choose(candidates: candidates + [other], focusedWindow: other.window, same: ==)?.picker == 91)
        let none: [(window: Int, picker: Int)] = []
        precondition(FilePickerResolver.choose(candidates: none, focusedWindow: webWindow, same: ==) == nil)
        let parents = [1: webWindow, openPanel: chatWindow, 2: openPanel, 3: 2]
        precondition(!FilePickerResolver.contains(1, root: openPanel, parent: { parents[$0] }, same: ==),
                     "A web control outside the picker must not pass the focus check")
        precondition(FilePickerResolver.contains(3, root: openPanel, parent: { parents[$0] }, same: ==))
        precondition(!FilePickerResolver.contains(4, root: openPanel, parent: { $0 }, same: ==),
                     "Malformed parent chains must terminate")
        print("PASS: logged multi-window regression, ambiguous/absent pickers, focused picker preference, picker-only focus, cyclic parent chain")
    }
}
