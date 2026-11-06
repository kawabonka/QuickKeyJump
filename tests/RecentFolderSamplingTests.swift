import Foundation

@main
struct RecentFolderSamplingTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1000)
        let raw = "file:///tmp/A\nfile:///tmp/%E6%B5%8B%E8%AF%95%20folder\nfile:///tmp/a%0Ab\nfile:///tmp/file.txt\nx-apple-finder:search\nnot a URL\n"
        let valid = Set(["/tmp/A", "/tmp/测试 folder", "/tmp/a\nb"])
        let sampled = RecentFolderSampling.finderFolders(from: raw, sampledAt: now, isDirectory: { valid.contains($0) })
        precondition(sampled.map(\.path) == ["/tmp/A", "/tmp/测试 folder", "/tmp/a\nb"])
        precondition(sampled[0].modDate > sampled[1].modDate)
        let history = RecentFolder(name: "A", path: "/tmp/A", shortcut: "", modDate: .distantPast)
        let changed = RecentFolder(name: "B", path: "/tmp/B", shortcut: "", modDate: now.addingTimeInterval(-10))
        let merged = RecentFolderSampling.merge([history, changed] + sampled, ignoring: [], limit: 10)
        precondition(merged.first?.path == "/tmp/A", "Opening an unchanged folder must promote it")
        precondition(merged.filter { $0.path == "/tmp/A" }.count == 1)
        precondition(merged.first?.modDate == now, "Fresh observation must replace old history time")
        let reverseOrder = RecentFolderSampling.merge(sampled + [history, changed], ignoring: [], limit: 10)
        precondition(reverseOrder.map(\.path) == merged.map(\.path), "Background source completion order must not affect ranking")
        let ignored = RecentFolderSampling.merge(sampled, ignoring: ["/tmp/A"], limit: 2)
        precondition(!ignored.contains { $0.path == "/tmp/A" })
        precondition(ignored.map(\.shortcut) == ["1", "2"])
        let child = RecentFolder(name: "child", path: "/tmp/A/child", shortcut: "", modDate: now)
        precondition(RecentFolderSampling.merge([child], ignoring: ["/tmp/A"], limit: 10).isEmpty)
        let normalized = RecentFolder(name: "A", path: "/tmp/B/../A", shortcut: "", modDate: .distantPast)
        precondition(RecentFolderSampling.merge(sampled + [normalized], ignoring: [], limit: 10).count == sampled.count)
        precondition(RecentFolderSampling.merge(sampled, ignoring: [], limit: 0).isEmpty)
        print("PASS: unchanged open folders promoted; latest timestamp deduplication; source-order independence; ignored folders/subfolders; URL decoding; invalid sources; limits and shortcut numbering")
    }
}
