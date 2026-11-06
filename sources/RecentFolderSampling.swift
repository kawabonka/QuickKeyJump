import Foundation

struct RecentFolder: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let shortcut: String
    var modDate: Date = .distantPast
}

/// Shared merge rules for filesystem history, Spotlight and visible Finder folders.
enum RecentFolderSampling {
    static func merge(_ folders: [RecentFolder], ignoring ignoredPaths: [String], limit: Int) -> [RecentFolder] {
        var latest: [String: RecentFolder] = [:]
        for folder in folders {
            let path = (folder.path as NSString).standardizingPath
            guard path.hasPrefix("/"), !ignoredPaths.contains(where: {
                path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/")
            }) else { continue }
            if let old = latest[path], old.modDate >= folder.modDate { continue }
            latest[path] = RecentFolder(name: folder.name, path: path, shortcut: "", modDate: folder.modDate)
        }
        return latest.values.sorted {
            $0.modDate == $1.modDate ? $0.path < $1.path : $0.modDate > $1.modDate
        }.prefix(max(0, limit)).enumerated().map { index, folder in
            RecentFolder(name: folder.name, path: folder.path, shortcut: String(index + 1), modDate: folder.modDate)
        }
    }

    /// Finder returns encoded file URLs, so spaces, commas and newlines in names
    /// survive the line-delimited transport without splitting a filesystem path.
    static func finderFolders(from output: String, sampledAt: Date,
                              isDirectory: (String) -> Bool) -> [RecentFolder] {
        output.split(separator: "\n").enumerated().compactMap { index, line in
            guard let url = URL(string: String(line)), url.isFileURL else { return nil }
            let path = url.standardizedFileURL.path
            guard isDirectory(path) else { return nil }
            let name = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
            return RecentFolder(name: name, path: path, shortcut: "",
                                modDate: sampledAt.addingTimeInterval(-Double(index) * 0.001))
        }
    }
}
