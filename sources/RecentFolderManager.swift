import Foundation
import Combine

// MARK: - 数据模型

/// 表示一个最近使用的文件夹条目
struct RecentFolder: Identifiable {
    let id = UUID()
    let name: String       // 显示名称（目录名）
    let path: String       // 完整路径（已展开~）
    let shortcut: String   // 快捷键数字（1-5）
    var modDate: Date = .distantPast  // 最近使用时间（用于全局倒序排列）
}

// MARK: - 错误定义

/// RecentFolderManager 可能遇到的错误类型
enum RecentFolderError: Error, LocalizedError {
    case plistNotFound           // Finder偏好设置文件不存在
    case invalidPlistFormat      // PLIST文件格式无效
    case recentFoldersKeyMissing // FXRecentFolders键不存在
    case emptyRecentFolders      // 最近文件夹列表为空
    case bookmarkResolutionFailed(Data) // Bookmark解析失败，附原始数据
    case pathExtractionFailed    // 从数据中提取路径失败
    
    var errorDescription: String? {
        switch self {
        case .plistNotFound:
            return "Finder偏好设置文件不存在"
        case .invalidPlistFormat:
            return "PLIST文件格式无效"
        case .recentFoldersKeyMissing:
            return "FXRecentFolders键不存在"
        case .emptyRecentFolders:
            return "最近文件夹列表为空"
        case .bookmarkResolutionFailed:
            return "Bookmark解析失败"
        case .pathExtractionFailed:
            return "路径提取失败"
        }
    }
}

// MARK: - 核心管理类

/// 管理最近使用的文件夹列表
///
/// 从 macOS Finder 的偏好设置中读取 `FXRecentFolders` 键值，
/// 解析其中的书签数据和URL字符串，生成可供UI展示的最近文件夹列表。
///
/// 使用示例：
/// ```swift
/// let manager = RecentFolderManager()
/// manager.loadRecentFolders(maxResults: 5)
/// let firstFolder = manager.folder(at: 0)
/// ```
final class RecentFolderManager: ObservableObject {
    
    // MARK: 发布属性
    
    /// 最近使用的文件夹列表，已按时间排序（索引0为最新）
    @Published var folders: [RecentFolder] = []
    
    // MARK: 私有常量
    
    /// Finder偏好设置文件路径
    private let finderPlistPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Preferences/com.apple.finder.plist"
    }()
    
    /// FXRecentFolders键名
    private let recentFoldersKey = "FXRecentFolders"
    
    /// 日志分类标识
    private let logPrefix = "[RecentFolderManager]"
    
    // MARK: 初始化
    
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // 初始化时自动加载
        loadRecentFolders()

        // 忽视清单变化时自动刷新跳转列表
        IgnoreListManager.shared.$paths
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadRecentFolders() }
            .store(in: &cancellables)
    }
    
    // MARK: 公开接口
    
    /// 加载最近使用的目录列表
    ///
    /// 从 `~/Library/Preferences/com.apple.finder.plist` 读取 `FXRecentFolders`，
    /// 解析其中的目录条目，过滤掉不存在的目录，结果存入 `folders` 属性。
    ///
    /// - Parameter maxResults: 最多返回几条记录，默认为5（对应快捷键1-5）
    func loadRecentFolders(maxResults: Int = 5) {
        var combined: [RecentFolder] = []

        // 1. Finder 最近文件夹 (FXRecentFolders)
        do {
            let plistData = try readFinderPlist()
            let arr = try extractRecentFoldersArray(from: plistData)
            combined = try parseRecentFolders(from: arr)
        } catch {
            print("\(logPrefix) Finder 最近文件夹加载失败: \(error.localizedDescription)")
        }

        // 2. 常用根目录（Downloads 不再强制置顶，按实际修改时间参与排序）
        let downloadsPath = expandTilde(in: "~/Downloads")
        if validateDirectory(at: downloadsPath) {
            appendUnique(&combined, RecentFolder(
                name: "Downloads",
                path: downloadsPath,
                shortcut: "",
                modDate: modificationDate(of: downloadsPath)
            ))
        }

        // 3. Downloads / Desktop / Documents 最近活跃子目录
        for sub in recentSubfolders(in: ["~/Downloads", "~/Desktop", "~/Documents"]) {
            appendUnique(&combined, sub)
        }

        // 4. 全局按最近使用时间倒序（最新在最上面）
        combined.sort { $0.modDate > $1.modDate }

        // 4.1 过滤忽视清单（清单内目录及其子目录不纳入候选）
        combined = combined.filter { !IgnoreListManager.shared.isIgnored($0.path) }

        // 5. 先展示快速结果
        let fast = Array(combined.prefix(maxResults)).enumerated().map { (i, f) in
            RecentFolder(name: f.name, path: f.path, shortcut: String(i + 1))
        }
        DispatchQueue.main.async { [weak self] in self?.folders = fast }

        // 6. 异步 Spotlight 搜索最近 7 天修改过的目录（涵盖粘贴/下载/保存路径）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let manager = self else { return }
            let spotlight = manager.recentFoldersFromSpotlight()
            var merged = combined
            for f in spotlight {
                manager.appendUnique(&merged, f)
            }
            merged.sort { $0.modDate > $1.modDate }
            merged = merged.filter { !IgnoreListManager.shared.isIgnored($0.path) }
            let result = Array(merged.prefix(maxResults)).enumerated().map { (i, f) in
                RecentFolder(name: f.name, path: f.path, shortcut: String(i + 1))
            }
            DispatchQueue.main.async { self?.folders = result }
        }
    }

    /// 按路径去重追加（保留先出现的条目及其时间戳）
    private func appendUnique(_ list: inout [RecentFolder], _ folder: RecentFolder) {
        if !list.contains(where: { $0.path == folder.path }) {
            list.append(folder)
        }
    }

    /// 获取目录/文件的最后修改时间，失败返回 .distantPast
    private func modificationDate(of path: String) -> Date {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return .distantPast
        }
        return date
    }

    /// 扫描指定目录下最近 7 天修改过的子目录
    private func recentSubfolders(in roots: [String]) -> [RecentFolder] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        var results: [RecentFolder] = []
        for root in roots {
            let full = expandTilde(in: root)
            guard let items = try? fm.contentsOfDirectory(atPath: full) else { continue }
            for item in items {
                let path = full + "/" + item
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let modDate = attrs[.modificationDate] as? Date,
                      modDate > cutoff,
                      validateDirectory(at: path) else { continue }
                results.append(RecentFolder(name: item, path: path, shortcut: "", modDate: modDate))
            }
        }
        results.sort {
            let ma = (try? fm.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date ?? .distantPast
            let mb = (try? fm.attributesOfItem(atPath: $1.path))?[.modificationDate] as? Date ?? .distantPast
            return ma > mb
        }
        return results
    }

    /// Spotlight 搜索最近 7 天修改过的目录
    private func recentFoldersFromSpotlight() -> [RecentFolder] {
        let p = Process()
        p.launchPath = "/usr/bin/mdfind"
        p.arguments = ["-onlyin", NSHomeDirectory(),
                       "kMDItemContentModificationDate >= $time.today(-7) && kMDItemContentType == public.folder"]
        let pipe = Pipe(); p.standardOutput = pipe
        try? p.run()
        // 3 秒超时
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if p.isRunning { p.terminate() }
        }
        p.waitUntilExit()
        guard let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return [] }
        var results: [RecentFolder] = []
        for path in out.components(separatedBy: "\n") {
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, validateDirectory(at: trimmed) else { continue }
            let name = URL(fileURLWithPath: trimmed).lastPathComponent
            results.append(RecentFolder(name: name, path: trimmed, shortcut: "", modDate: modificationDate(of: trimmed)))
        }
        return results
    }
    
    /// 根据索引获取目录
    ///
    /// - Parameter index: 目录索引（0-based）
    /// - Returns: 对应的RecentFolder，索引越界时返回nil
    func folder(at index: Int) -> RecentFolder? {
        guard index >= 0, index < folders.count else {
            return nil
        }
        return folders[index]
    }
    
    /// 手动刷新最近文件夹列表
    /// 等同于调用 loadRecentFolders()
    func refresh() {
        loadRecentFolders()
    }
    
    // MARK: 私有方法 - 文件读取
    
    /// 读取Finder的PLIST文件内容
    ///
    /// - Returns: 解析后的PLIST字典
    /// - Throws: RecentFolderError
    private func readFinderPlist() throws -> [String: Any] {
        let fileURL = URL(fileURLWithPath: finderPlistPath)
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: finderPlistPath) else {
            throw RecentFolderError.plistNotFound
        }
        
        // 读取并解析PLIST
        let data = try Data(contentsOf: fileURL)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        
        guard let dictionary = plist as? [String: Any] else {
            throw RecentFolderError.invalidPlistFormat
        }
        
        return dictionary
    }
    
    /// 从PLIST字典中提取FXRecentFolders数组
    ///
    /// - Parameter plist: Finder PLIST字典
    /// - Returns: FXRecentFolders数组
    /// - Throws: RecentFolderError
    private func extractRecentFoldersArray(
        from plist: [String: Any]
    ) throws -> [[String: Any]] {
        guard let recentFolders = plist[recentFoldersKey] as? [[String: Any]] else {
            throw RecentFolderError.recentFoldersKeyMissing
        }
        
        guard !recentFolders.isEmpty else {
            throw RecentFolderError.emptyRecentFolders
        }
        
        return recentFolders
    }
    
    // MARK: 私有方法 - 数据解析
    
    /// 解析FXRecentFolders数组为RecentFolder列表
    ///
    /// - Parameters:
    ///   - array: FXRecentFolders原始数组
    ///   - maxResults: 最多返回几条
    /// - Returns: 解析后的RecentFolder数组
    private func parseRecentFolders(
        from array: [[String: Any]]
    ) throws -> [RecentFolder] {
        var results: [RecentFolder] = []
        // 收集上限：仅为排序提供足够样本，最终会截断到 maxResults
        let maxCollect = 50

        for item in array {
            guard results.count < maxCollect else { break }

            // 尝试解析路径
            if let path = resolvePath(from: item) {
                // 展开~为完整路径
                let expandedPath = expandTilde(in: path)

                // 验证目录是否存在且确实是目录
                if validateDirectory(at: expandedPath) {
                    let name = extractFolderName(from: expandedPath)
                    // 优先使用 Finder 记录的访问时间，缺失时回退到文件修改时间
                    let date = (item["date"] as? Date) ?? modificationDate(of: expandedPath)

                    let folder = RecentFolder(
                        name: name,
                        path: expandedPath,
                        shortcut: "",
                        modDate: date
                    )
                    results.append(folder)
                } else {
                    print("\(logPrefix) 目录不存在或不是有效目录: \(expandedPath)")
                }
            }
        }

        return results
    }
    
    /// 从单个FXRecentFolders条目解析路径
    ///
    /// 支持两种数据格式：
    /// 1. `file-bookmark`: NSURLBookmarkData，通过resolveBookmarkData解析
    /// 2. `file-data`: 包含 `_CFURLString` 键的字典，直接读取URL字符串
    ///
    /// - Parameter item: 单个FXRecentFolders条目
    /// - Returns: 解析出的路径字符串，失败返回nil
    private func resolvePath(from item: [String: Any]) -> String? {
        // 尝试格式1: file-bookmark (bookmarkData)
        if let bookmarkData = item["file-bookmark"] as? Data {
            if let path = resolveBookmarkPath(from: bookmarkData) {
                return path
            }
            // Bookmark解析失败，尝试fallback从原始数据提取
            if let fallbackPath = extractPathFromRawData(bookmarkData) {
                print("\(logPrefix) Bookmark解析失败，使用fallback路径: \(fallbackPath)")
                return fallbackPath
            }
            return nil
        }
        
        // 尝试格式2: file-data (包含_CFURLString的字典)
        if let fileData = item["file-data"] as? [String: Any] {
            // 格式2a: _CFURLString包含完整URL
            if let urlString = fileData["_CFURLString"] as? String {
                return normalizeURLString(urlString)
            }
            // 格式2b: _CFURLStringData包含Data
            if let urlData = fileData["_CFURLStringData"] as? Data {
                if let urlString = String(data: urlData, encoding: .utf8) {
                    return normalizeURLString(urlString)
                }
            }
        }
        
        // 未知格式，尝试直接提取name字段作为显示名
        if let name = item["name"] as? String, !name.isEmpty {
            print("\(logPrefix) 无法解析路径，但有名称: \(name)")
        }
        
        return nil
    }
    
    /// 使用bookmarkData解析路径
    ///
    /// - Parameter data: NSURLBookmarkData
    /// - Returns: 解析出的路径字符串
    private func resolveBookmarkPath(from data: Data) -> String? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("\(logPrefix) Bookmark数据已过期，但仍尝试使用")
            }
            
            // 获取文件路径
            let path = url.path
            guard !path.isEmpty else {
                return nil
            }
            
            return path
            
        } catch {
            print("\(logPrefix) Bookmark解析失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 从原始Data中提取file://或/Users/路径（fallback方案）
    ///
    /// 当bookmark解析失败时，尝试在原始数据中搜索已知的文件路径模式。
    /// 这在某些系统配置下是有效的fallback方案。
    ///
    /// - Parameter data: 原始bookmarkData
    /// - Returns: 提取出的路径字符串
    private func extractPathFromRawData(_ data: Data) -> String? {
        // 将Data转为字符串
        guard let rawString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        // 方法1: 查找 file:// 前缀的URL
        if let range = rawString.range(of: "file://") {
            let start = range.lowerBound
            let substring = rawString[start...]
            // 提取到下一个不可见字符或字符串结尾
            let pathEnd = substring.firstIndex { char in
                char < " "  // ASCII 控制字符 (< 0x20)
            } ?? substring.endIndex
            let urlString = String(substring[..<pathEnd])
            
            if let url = URL(string: urlString), !url.path.isEmpty {
                return url.path
            }
        }
        
        // 方法2: 查找 /Users/ 开头的绝对路径
        if let range = rawString.range(of: "/Users/") {
            let substring = rawString[range.lowerBound...]
            let pathEnd = substring.firstIndex { char in
                char < " "  // ASCII 控制字符 (< 0x20) 包括 \n \t \0
            } ?? substring.endIndex
            let path = String(substring[..<pathEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if path.count > "/Users/".count {
                return path
            }
        }
        
        return nil
    }
    
    // MARK: 私有方法 - 辅助工具
    
    /// 将URL字符串规范化为文件路径
    ///
    /// 处理 file:///path/to/folder 格式，提取其中的路径部分
    ///
    /// - Parameter urlString: 原始URL字符串
    /// - Returns: 规范化后的路径
    private func normalizeURLString(_ urlString: String) -> String {
        if urlString.hasPrefix("file://") {
            // file://localhost/path 或 file:///path 格式
            var path = urlString
            path.removeFirst("file://".count)
            if path.hasPrefix("localhost") {
                path.removeFirst("localhost".count)
            }
            return path
        }
        return urlString
    }
    
    /// 展开路径中的~为用户主目录
    ///
    /// - Parameter path: 可能包含~的路径
    /// - Returns: 展开后的完整路径
    private func expandTilde(in path: String) -> String {
        guard path.hasPrefix("~") else {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.count == 1 {
            return home
        }
        // ~username 格式
        if path.hasPrefix("~/") {
            return home + path.dropFirst(1)
        }
        // ~otheruser - 返回原样（无法展开其他用户目录）
        return path
    }
    
    /// 验证指定路径是否是存在的目录
    ///
    /// - Parameter path: 要验证的路径
    /// - Returns: 是否是有效目录
    private func validateDirectory(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }
    
    /// 从完整路径中提取目录名称
    ///
    /// - Parameter path: 完整路径
    /// - Returns: 目录名（路径最后一部分）
    private func extractFolderName(from path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let lastComponent = trimmedPath.split(separator: "/").last {
            return String(lastComponent)
        }
        return path
    }
}
