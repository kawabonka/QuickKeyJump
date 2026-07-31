import Foundation
import Combine

/// 忽视清单：清单内的目录及其子目录不会出现在快速跳转候选列表中
/// 首次启动内置默认忽视 macOS 用户资源库（~/Library），用户可在设置中删除
final class IgnoreListManager: ObservableObject {
    static let shared = IgnoreListManager()

    /// 当前忽视的目录（绝对路径，已标准化）
    @Published private(set) var paths: [String] = []

    private let defaultsKey = "QKJIgnoredFolders"

    private init() {
        load()
    }

    // MARK: - 读取 / 持久化

    /// 从 UserDefaults 加载忽视清单
    ///
    /// 首次启动（从未设置过）时写入内置默认项：macOS 用户资源库 ~/Library，
    /// 并立即持久化，之后用户增删均以用户配置为准。
    func load() {
        let stored = UserDefaults.standard.object(forKey: defaultsKey) as? [String]
        if let stored {
            paths = normalize(stored)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            paths = [home + "/Library"]
            save()
        }
    }

    /// 标准化并去重路径列表
    private func normalize(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw
            .map { ($0 as NSString).standardizingPath }
            .filter { !$0.isEmpty && $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    /// 判断路径是否被忽视（路径本身，或位于任一忽视目录之下）
    func isIgnored(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        return paths.contains { ignored in
            normalized == ignored || normalized.hasPrefix(ignored + "/")
        }
    }

    // MARK: - 增删

    /// 添加一个忽视目录（已存在或非法路径则忽略）
    func add(_ path: String) {
        let normalized = (path as NSString).standardizingPath
        guard !normalized.isEmpty,
              normalized.hasPrefix("/"),
              !paths.contains(where: { $0 == normalized }) else { return }
        paths.append(normalized)
        save()
    }

    /// 移除指定索引的忽视目录
    func remove(at index: Int) {
        guard paths.indices.contains(index) else { return }
        paths.remove(at: index)
        save()
    }

    private func save() {
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }
}
