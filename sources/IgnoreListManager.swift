import Foundation
import Combine

/// 忽视清单：清单内的目录及其子目录不会出现在快速跳转候选列表中
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
    func load() {
        paths = (UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
            .map { ($0 as NSString).standardizingPath }
            .filter { !$0.isEmpty && $0.hasPrefix("/") }
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
