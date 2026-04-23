# macOS 最近使用目录数据源 - 技术调研报告

## 目录
1. [核心数据源概览](#1-核心数据源概览)
2. [方案一：FXRecentFolders（推荐主方案）](#2-方案一fxrecentfolders推荐主方案)
3. [方案二：NSNavRecentPlaces（备选方案）](#3-方案二nsnavrecentplaces备选方案)
4. [方案三：LSSharedFileList.sfl2（不推荐）](#4-方案三lssharedfilelistsfl2不推荐)
5. [方案四：NSDocumentController（仅限文档）](#5-方案四nsdocumentcontroller仅限文档)
6. [方案五：NSMetadataQuery（备选方案）](#6-方案五nsmetadataquery备选方案)
7. [BookmarkData 解析详解](#7-bookmarkdata-解析详解)
8. [完整 Swift 代码实现](#8-完整-swift-代码实现)
9. [可行性评级对比表](#9-可行性评级对比表)
10. [注意事项与最佳实践](#10-注意事项与最佳实践)

---

## 1. 核心数据源概览

macOS 存储最近使用目录信息有多个数据源，按推荐程度排序：

| 优先级 | 数据源 | 文件路径 | 条目数 | 内容 |
|--------|--------|----------|--------|------|
| ★★★★★ | FXRecentFolders | `~/Library/Preferences/com.apple.finder.plist` | 最多10条 | Finder 最近访问的文件夹 |
| ★★★★☆ | NSNavRecentPlaces / NSOSPRecentPlaces | `~/Library/Preferences/.GlobalPreferences.plist` | 可变 | 保存/打开对话框最近位置 |
| ★★★☆☆ | SFL2 RecentDocuments | `~/Library/Application Support/com.apple.sharedfilelist/*.sfl2` | 可变 | 系统级最近文档（非目录） |
| ★★☆☆☆ | NSDocumentController | 内存API | 应用级 | 仅限当前应用的最近文档 |
| ★★☆☆☆ | NSMetadataQuery | Spotlight索引 | 动态查询 | 基于文件系统元数据实时查询 |

---

## 2. 方案一：FXRecentFolders（推荐主方案）

### 2.1 基本信息

- **文件位置**: `~/Library/Preferences/com.apple.finder.plist`
- **Key**: `FXRecentFolders`
- **存储方式**: 二进制 plist（需用 `NSDictionary(contentsOfFile:)` 或 `plutil` 转换）
- **条目数量**: 最多10条（Item 0 最新，Item 9 最旧）
- **已按时间排序**: ✅ 是，Item 0 为最近访问

### 2.2 条目结构

每个条目是一个 Dictionary，包含以下字段：

```
Item N = {
    "name"          => String : 显示名称（如 "Downloads"）
    "file-bookmark" => Data   : NSURL bookmarkData（主要格式，modern）
    // 或
    "file-data"     => Dict   : {（旧格式，较老系统）
        "_CFURLString"     => String : "file:///Users/xxx/Downloads/"
        "_CFURLStringType" => Number : 15
    }
}
```

**两种格式说明**：
- `file-bookmark`: 现代格式，bookmarkData 字节流（以 `book` 或 `alis` 头部开头）
- `file-data`: 旧格式，直接包含 URL 字符串，较容易解析但可能在新系统中不出现

### 2.3 bookmarkData 头部类型

| 头部魔术数 | 类型 | 说明 |
|-----------|------|------|
| `book` (0x626F6F6B) | 现代 bookmark | 包含完整文件定位信息，可能含图标数据（体积较大） |
| `alis` (0x616C6973) | 旧式 alias | Classic Mac OS 兼容格式，较薄弱的包装器 |
| ` Bud` | 资源分支 | 极少数情况 |

### 2.4 权限与 TCC

- **读取 `~/Library/Preferences/com.apple.finder.plist 是否需要特殊权限？**
  - ✅ **不需要** - 用户自己的 Preferences 目录下的文件，普通用户权限即可读取
  - 不需要 Full Disk Access
  - 不需要 TCC 授权（kTCCServiceFileProvider等）
  - 沙盒App可能需要 `com.apple.security.files.user-selected.read-write`

### 2.5 完整 Swift 代码

```swift
import Foundation

/// 表示一个最近使用的目录
struct RecentFolder: Identifiable, CustomStringConvertible {
    let id = UUID()
    let name: String
    let url: URL
    let isReachable: Bool
    
    var description: String {
        "\(name) -> \(url.path) \(isReachable ? "✅" : "❌")"
    }
}

/// FXRecentFolders 读取和解析器
final class FXRecentFoldersReader {
    
    /// 错误类型
    enum ReaderError: Error, CustomStringConvertible {
        case plistNotFound
        case plistReadFailed(String)
        case noFXRecentFoldersKey
        case invalidEntryFormat(Int)
        case bookmarkResolveFailed(Int, String)
        
        var description: String {
            switch self {
            case .plistNotFound:
                return "找不到 com.apple.finder.plist"
            case .plistReadFailed(let detail):
                return "读取 plist 失败: \(detail)"
            case .noFXRecentFoldersKey:
                return "plist 中不存在 FXRecentFolders 键"
            case .invalidEntryFormat(let index):
                return "条目 \(index) 格式无效"
            case .bookmarkResolveFailed(let index, let detail):
                return "条目 \(index) bookmark 解析失败: \(detail)"
            }
        }
    }
    
    /// plist 文件路径
    private var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Preferences")
            .appendingPathComponent("com.apple.finder.plist")
    }
    
    // MARK: - 主入口
    
    /// 读取并解析 FXRecentFolders
    /// - Parameters:
    ///   - validateExistence: 是否验证目录仍然存在
    ///   - maxResults: 最大返回数量（默认全部）
    /// - Returns: 按时间排序的最近目录列表（最新的在前）
    func readRecentFolders(
        validateExistence: Bool = true,
        maxResults: Int? = nil
    ) -> Result<[RecentFolder], ReaderError> {
        
        // 1. 读取 plist
        guard let plist = NSDictionary(contentsOf: plistURL) else {
            return .failure(.plistReadFailed("无法加载 plist，路径: \(plistURL.path)"))
        }
        
        // 2. 获取 FXRecentFolders 数组
        guard let recentFolders = plist["FXRecentFolders"] as? [Any] else {
            return .failure(.noFXRecentFoldersKey)
        }
        
        // 3. 解析每个条目
        var results: [RecentFolder] = []
        
        for (index, entry) in recentFolders.enumerated() {
            guard let dict = entry as? [String: Any] else {
                continue // 跳过无效条目
            }
            
            // 获取显示名称
            let name = dict["name"] as? String ?? "Unknown"
            
            // 尝试解析 URL（两种格式）
            if let urlResult = parseEntry(dict: dict, index: index) {
                let isReachable = validateExistence
                    ? FileManager.default.fileExists(atPath: urlResult.path)
                    : true
                
                results.append(RecentFolder(
                    name: name,
                    url: urlResult,
                    isReachable: isReachable
                ))
            }
        }
        
        // 4. 如果验证存在性，过滤掉不可达的
        if validateExistence {
            results = results.filter { $0.isReachable }
        }
        
        // 5. 限制数量
        if let max = maxResults, results.count > max {
            results = Array(results.prefix(max))
        }
        
        return .success(results)
    }
    
    // MARK: - 条目解析
    
    /// 解析单个条目，优先尝试 file-bookmark，fallback 到 file-data
    private func parseEntry(dict: [String: Any], index: Int) -> URL? {
        // 方式1: 尝试解析 file-bookmark（现代格式）
        if let bookmarkData = dict["file-bookmark"] as? Data {
            if let url = resolveBookmark(bookmarkData, index: index) {
                return url
            }
        }
        
        // 方式2: 尝试解析 file-data（旧格式）
        if let fileData = dict["file-data"] as? [String: Any] {
            if let urlString = fileData["_CFURLString"] as? String {
                return URL(string: urlString)
            }
        }
        
        // 方式3: 尝试 "book" 键（某些版本使用）
        if let bookmarkData = dict["book"] as? Data {
            if let url = resolveBookmark(bookmarkData, index: index) {
                return url
            }
        }
        
        return nil
    }
    
    // MARK: - Bookmark 解析
    
    /// 使用 NSURL API 解析 bookmarkData
    private func resolveBookmark(_ data: Data, index: Int) -> URL? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                // bookmark 已过期但仍可解析路径
                print("[WARN] 条目 \(index) 的 bookmark 已过期，路径可能不准确")
            }
            
            return url
        } catch {
            print("[ERROR] Bookmark 解析失败 (条目 \(index)): \(error)")
            
            // Fallback: 尝试从 bookmarkData 中直接提取路径字符串
            return extractPathFromBookmarkFallback(data)
        }
    }
    
    /// Fallback: 从 bookmarkData 原始数据中尝试提取路径
    /// bookmarkData 内部以纯文本形式包含文件路径，可作为最后手段
    private func extractPathFromBookmarkFallback(_ data: Data) -> URL? {
        // 将 Data 转为 String，查找 file:// 或 /Users/ 等路径模式
        if let rawString = String(data: data, encoding: .utf8) {
            // 尝试查找 file:// URL
            if let range = rawString.range(of: "file://") {
                let substring = rawString[range.lowerBound...]
                // 截取到下一个空字节或异常字符
                if let url = URL(string: String(substring.prefix(while: { $0 != "\0" }))) {
                    return url
                }
            }
        }
        
        // 尝试 ASCII 编码
        let asciiString = data.reduce("") { result, byte in
            result + (byte >= 32 && byte < 127 ? String(UnicodeScalar(byte)) : "")
        }
        if let range = asciiString.range(of: "/Users/") {
            let path = String(asciiString[range.lowerbound...])
                .components(separatedBy: CharacterSet.controlCharacters)
                .first ?? ""
            if !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        }
        
        return nil
    }
}

// MARK: - 使用示例

func demo() {
    let reader = FXRecentFoldersReader()
    
    switch reader.readRecentFolders(validateExistence: true, maxResults: 10) {
    case .success(let folders):
        print("=== Finder 最近使用的目录 ===")
        for (index, folder) in folders.enumerated() {
            print("\(index + 1). \(folder.name)")
            print("   路径: \(folder.url.path)")
            print("   可达: \(folder.isReachable ? "是" : "否")")
        }
    case .failure(let error):
        print("读取失败: \(error)")
    }
}
```

---

## 3. 方案二：NSNavRecentPlaces（备选方案）

### 3.1 基本信息

- **文件位置**: `~/Library/Preferences/.GlobalPreferences.plist`
- **旧 Key**: `NSNavRecentPlaces`（macOS Sonoma 及之前）
- **新 Key**: `NSOSPRecentPlaces`（macOS Sequoia+）
- **内容**: 保存/打开对话框（NSOpenPanel/NSSavePanel）中最近使用的位置

### 3.2 数据结构

```swift
// NSNavRecentPlaces 是一个字符串数组，存储路径
[
    "/Users/username/Documents",
    "/Users/username/Desktop/Projects",
    "/Volumes/ExternalDrive/Data"
]
```

### 3.3 Swift 代码

```swift
func readNSNavRecentPlaces() -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let globalPrefs = home
        .appendingPathComponent("Library")
        .appendingPathComponent("Preferences")
        .appendingPathComponent(".GlobalPreferences.plist")
    
    guard let plist = NSDictionary(contentsOf: globalPrefs) else {
        return []
    }
    
    // 尝试新旧两个 key
    let paths = (plist["NSOSPRecentPlaces"] as? [String])
        ?? (plist["NSNavRecentPlaces"] as? [String])
        ?? []
    
    return paths.compactMap { path -> URL? in
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: path) ? url : nil
    }
}
```

### 3.4 优缺点

| 优点 | 缺点 |
|------|------|
| 无需解析 bookmark，直接是字符串路径 | Key 名称在不同 macOS 版本间变化 |
| 数据来源独立（对话框历史 vs Finder 历史） | 只包含用户通过对话框访问的路径 |
| 读取极其简单 | 条目数量不固定 |

---

## 4. 方案三：LSSharedFileList.sfl2（不推荐）

### 4.1 背景

- **位置**: `~/Library/Application Support/com.apple.sharedfilelist/`
- **文件**: `com.apple.LSSharedFileList.RecentDocuments.sfl2` 等
- **状态**: ⚠️ **LSSharedFileList API 已在 macOS 10.11 中被标记为 Deprecated**
- **苹果官方回复**: "Shared file lists are no longer supported. There is no exact replacement API."

### 4.2 文件格式

.sfl2 文件是 NSKeyedArchiver 格式的二进制 plist，结构非常复杂：

```
$version => 100000
$objects => [ ... 嵌套对象数组 ... ]
$archiver => "NSKeyedArchiver"
$top => { root => reference }
```

items 数组中的每个条目包含：
- `name`: 显示名称
- `bookmark`: bookmarkData
- `order`: 排序号
- `uniqueIdentifier`: UUID
- `properties`: 额外属性字典

### 4.3 为什么不推荐

1. **API 已废弃** - 苹果不再支持，可能在未来版本中移除
2. **格式复杂** - 需要处理 NSKeyedArchiver 反序列化
3. **主要是文档** - RecentDocuments 存储的是文件不是目录
4. **没有 RecentFolders** - sfl2 中没有专门的 RecentFolders 列表

---

## 5. 方案四：NSDocumentController（仅限文档）

### 5.1 API

```swift
// 获取当前应用的最近文档 URL
let recentURLs = NSDocumentController.shared.recentDocumentURLs
```

### 5.2 限制

- 只返回**文件**（文档），不返回**目录**
- 只包含**当前应用**打开的文档，不是系统级的
- 对于目录跳转工具**不适用**

---

## 6. 方案五：NSMetadataQuery（备选方案）

### 6.1 概念

使用 Spotlight 的 NSMetadataQuery 实时查询文件系统元数据，查找最近访问的目录。

### 6.2 Swift 代码示例

```swift
import Foundation

class RecentDirectoriesQuery: NSObject, ObservableObject {
    @Published var recentDirectories: [URL] = []
    
    private let query = NSMetadataQuery()
    
    func startQuery(hoursBack: Int = 24 * 7) {
        // 查询最近 N 小时内被访问过的目录
        query.notificationBatchingInterval = 1
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        
        // 使用 NSPredicate 构建查询条件
        let predicate = NSPredicate(format:
            "kMDItemContentType == 'public.folder' && " +
            "kMDItemLastUsedDate >= $time.now(-\(hoursBack).hours)"
        )
        query.predicate = predicate
        
        // 排序：最近使用的在前
        let sort = NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)
        query.sortDescriptors = [sort]
        
        // 监听通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryUpdated),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        
        query.start()
    }
    
    @objc private func queryUpdated(_ notification: Notification) {
        query.stop()
        
        guard let results = query.results as? [NSMetadataItem] else { return }
        
        recentDirectories = results.compactMap { item -> URL? in
            item.value(forAttribute: kMDItemPath as String) as? String
        }.map { URL(fileURLWithPath: $0) }
    }
}
```

### 6.3 优缺点

| 优点 | 缺点 |
|------|------|
| 不依赖 plist 文件，直接从文件系统获取 | 需要 Spotlight 索引启用 |
| 可以跨时间范围查询 | 查询有性能开销 |
| 自动去重 | 首次查询可能较慢 |
| 可以获取"真正最近使用"而非"最近打开" | 需要处理隐私权限（TCC） |

---

## 7. BookmarkData 解析详解

### 7.1 核心 API

```swift
/// 解析 bookmarkData 的标准方法
/// - Parameters:
///   - data: bookmarkData 字节
///   - options: 解析选项
///   - bookmarkDataIsStale: 输出参数，表示 bookmark 是否已过期
/// - Returns: 解析出的 URL
func resolveBookmarkData(
    _ data: Data,
    options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting],
    bookmarkDataIsStale: inout Bool
) throws -> URL {
    return try URL(
        resolvingBookmarkData: data,
        options: options,
        relativeTo: nil,
        bookmarkDataIsStale: &bookmarkDataIsStale
    )
}
```

### 7.2 解析选项

| 选项 | 说明 |
|------|------|
| `.withoutUI` | 禁止显示 UI（如挂载对话框） |
| `.withoutMounting` | 禁止自动挂载卷 |
| `.withSecurityScope` | 解析安全作用域 bookmark（沙盒App需要） |

### 7.3 处理 stale bookmark

```swift
func resolveWithStaleHandling(_ bookmarkData: Data) -> URL? {
    var isStale = false
    
    do {
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        if isStale {
            // bookmark 已过期，尝试刷新
            do {
                let freshData = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                // 保存 freshData 以备后用
                print("Bookmark 已刷新")
            } catch {
                print("刷新 bookmark 失败: \(error)")
            }
        }
        
        return url
    } catch {
        print("解析失败: \(error)")
        return nil
    }
}
```

### 7.4 获取 Bookmark 内部信息（不解析完整 URL）

```swift
/// 不解析完整 URL，仅从 bookmarkData 中获取特定属性
func getBookmarkInfo(_ data: Data) -> [URLResourceKey: Any]? {
    let keys: [URLResourceKey] = [
        .pathKey,           // 最后已知路径
        .volumeURLKey,      // 卷 URL
        .volumeNameKey,     // 卷名称
        .nameKey,           // 文件/目录名称
        .isDirectoryKey     // 是否是目录
    ]
    
    do {
        let values = try URL.resourceValues(
            forKeys: Set(keys),
            fromBookmarkData: data
        )
        return values.allValues
    } catch {
        print("获取 bookmark 信息失败: \(error)")
        return nil
    }
}
```

### 7.5 第三方 Bookmark 解析库

推荐 **[dagronf/Bookmark](https://github.com/dagronf/Bookmark)** Swift 包装库：

```swift
import Bookmark

// 创建 Bookmark
let bookmark = try Bookmark(bookmarkData: data)

// 解析并获取状态
try bookmark.resolving { resolved in
    print("URL: \(resolved.url)")
    print("是否过期: \(resolved.isStale)")
}
```

---

## 8. 完整 Swift 代码实现

### 8.1 生产级 RecentFolderManager

```swift
import Foundation

/// macOS 最近使用目录管理器
/// 综合多个数据源提供完整的最近目录列表
public final class RecentFolderManager {
    
    // MARK: - 配置
    
    public struct Configuration {
        /// 是否验证目录仍然存在
        public var validateExistence: Bool
        /// 最大返回数量
        public var maxResults: Int
        /// 是否包含 NSNavRecentPlaces 数据源
        public var includeNavPlaces: Bool
        /// 是否去重
        public var deduplicate: Bool
        
        public init(
            validateExistence: Bool = true,
            maxResults: Int = 20,
            includeNavPlaces: Bool = true,
            deduplicate: Bool = true
        ) {
            self.validateExistence = validateExistence
            self.maxResults = maxResults
            self.includeNavPlaces = includeNavPlaces
            self.deduplicate = deduplicate
        }
    }
    
    // MARK: - 错误
    
    public enum Error: Swift.Error {
        case sourceUnavailable(String)
        case permissionDenied(String)
        case parseFailure(String)
    }
    
    // MARK: - 属性
    
    private let fileManager = FileManager.default
    
    // MARK: - 主接口
    
    /// 获取综合的最近使用目录列表
    public func getRecentFolders(config: Configuration = Configuration()) -> [RecentFolderEntry] {
        var allFolders: [RecentFolderEntry] = []
        
        // 1. 从 FXRecentFolders 读取（最推荐，已按时间排序）
        if let fxFolders = try? readFXRecentFolders() {
            allFolders.append(contentsOf: fxFolders)
        }
        
        // 2. 从 NSNavRecentPlaces 读取
        if config.includeNavPlaces {
            if let navFolders = try? readNSNavRecentPlaces() {
                allFolders.append(contentsOf: navFolders)
            }
        }
        
        // 3. 去重（按路径）
        if config.deduplicate {
            var seenPaths = Set<String>()
            allFolders = allFolders.filter { entry in
                let path = entry.url.standardizedFileURL.path
                if seenPaths.contains(path) {
                    return false
                }
                seenPaths.insert(path)
                return true
            }
        }
        
        // 4. 验证存在性
        if config.validateExistence {
            allFolders = allFolders.filter { fileManager.fileExists(atPath: $0.url.path) }
        }
        
        // 5. 限制数量
        if allFolders.count > config.maxResults {
            allFolders = Array(allFolders.prefix(config.maxResults))
        }
        
        return allFolders
    }
    
    // MARK: - FXRecentFolders 读取
    
    private func readFXRecentFolders() throws -> [RecentFolderEntry] {
        let plistURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.finder.plist")
        
        guard fileManager.fileExists(atPath: plistURL.path) else {
            throw Error.sourceUnavailable("com.apple.finder.plist 不存在")
        }
        
        guard let plist = NSDictionary(contentsOf: plistURL),
              let recentFolders = plist["FXRecentFolders"] as? [Any] else {
            throw Error.parseFailure("FXRecentFolders 键不存在或格式错误")
        }
        
        return recentFolders.enumerated().compactMap { index, entry -> RecentFolderEntry? in
            guard let dict = entry as? [String: Any],
                  let name = dict["name"] as? String else { return nil }
            
            let url: URL? = self.parseFXEntry(dict: dict, index: index)
            
            guard let resolvedURL = url else { return nil }
            
            return RecentFolderEntry(
                name: name,
                url: resolvedURL,
                source: .fxRecentFolders,
                index: index
            )
        }
    }
    
    private func parseFXEntry(dict: [String: Any], index: Int) -> URL? {
        // 1. 尝试 file-bookmark
        if let bookmarkData = dict["file-bookmark"] as? Data {
            return resolveBookmarkData(bookmarkData)
        }
        
        // 2. 尝试 file-data（旧格式）
        if let fileData = dict["file-data"] as? [String: Any],
           let urlString = fileData["_CFURLString"] as? String {
            return URL(string: urlString)
        }
        
        // 3. 尝试 book 键
        if let bookmarkData = dict["book"] as? Data {
            return resolveBookmarkData(bookmarkData)
        }
        
        return nil
    }
    
    // MARK: - NSNavRecentPlaces 读取
    
    private func readNSNavRecentPlaces() throws -> [RecentFolderEntry] {
        let globalPrefsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/.GlobalPreferences.plist")
        
        guard let plist = NSDictionary(contentsOf: globalPrefsURL) else {
            throw Error.sourceUnavailable(".GlobalPreferences.plist 读取失败")
        }
        
        // 尝试新 key（Sequoia+）和旧 key
        let paths = (plist["NSOSPRecentPlaces"] as? [String])
            ?? (plist["NSNavRecentPlaces"] as? [String])
            ?? []
        
        return paths.enumerated().map { index, path in
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
            return RecentFolderEntry(
                name: name,
                url: url,
                source: .nsNavPlaces,
                index: index
            )
        }
    }
    
    // MARK: - Bookmark 解析
    
    private func resolveBookmarkData(_ data: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                // 过期但还能用，记录日志
            }
            
            return url
        } catch {
            // 标准解析失败，尝试 fallback
            return extractPathFromBookmarkFallback(data)
        }
    }
    
    /// 从 bookmarkData 原始数据中提取路径字符串
    private func extractPathFromBookmarkFallback(_ data: Data) -> URL? {
        // bookmarkData 内部包含可读的 URL 字符串
        // 查找 file:// 模式
        let searchString = "file://"
        let dataSize = data.count
        
        for i in 0..<(dataSize - searchString.count) {
            let subdata = data.subdata(in: i..<(i + searchString.utf8.count))
            if let str = String(data: subdata, encoding: .utf8), str == searchString {
                // 找到 file://，向后读取直到遇到 null 字节
                var urlBytes: [UInt8] = []
                var j = i
                while j < dataSize {
                    let byte = data[j]
                    if byte == 0 { break }
                    urlBytes.append(byte)
                    j += 1
                }
                
                if let urlStr = String(bytes: urlBytes, encoding: .utf8),
                   let url = URL(string: urlStr) {
                    return url
                }
            }
        }
        
        // 尝试直接查找 /Users/ 路径
        let usersPattern = "/Users/"
        for i in 0..<(dataSize - usersPattern.count) {
            let subdata = data.subdata(in: i..<(i + usersPattern.utf8.count))
            if let str = String(data: subdata, encoding: .utf8), str == usersPattern {
                var pathBytes: [UInt8] = []
                var j = i
                while j < dataSize {
                    let byte = data[j]
                    if byte < 32 || byte > 126 { break }
                    pathBytes.append(byte)
                    j += 1
                }
                
                if let path = String(bytes: pathBytes, encoding: .utf8) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        
        return nil
    }
}

// MARK: - 数据模型

public struct RecentFolderEntry: Identifiable, CustomStringConvertible {
    public let id = UUID()
    public let name: String
    public let url: URL
    public let source: DataSource
    public let index: Int
    
    public enum DataSource: String {
        case fxRecentFolders = "FXRecentFolders"
        case nsNavPlaces = "NSNavRecentPlaces"
        case metadataQuery = "NSMetadataQuery"
    }
    
    public var description: String {
        "[\(source.rawValue)#\(index)] \(name) -> \(url.path)"
    }
}

// MARK: - Data 下标扩展

extension Data {
    subscript(index: Int) -> UInt8 {
        self[self.index(self.startIndex, offsetBy: index)]
    }
}
```

### 8.2 使用示例

```swift
let manager = RecentFolderManager()

// 使用默认配置
let folders = manager.getRecentFolders()
for folder in folders {
    print("\(folder.name): \(folder.url.path)")
}

// 自定义配置
var config = RecentFolderManager.Configuration()
config.maxResults = 10
config.validateExistence = true
config.includeNavPlaces = true
config.deduplicate = true

let topFolders = manager.getRecentFolders(config: config)
```

---

## 9. 可行性评级对比表

| 方案 | 评级 | 获取难度 | 数据质量 | 维护风险 | 推荐场景 |
|------|------|----------|----------|----------|----------|
| **FXRecentFolders** | ⭐ **强烈推荐** | 低 | 高 | 低 | **主数据源** |
| NSNavRecentPlaces | ⭐ **可用** | 极低 | 中 | 中（Key名变化） | 补充数据源 |
| NSMetadataQuery | ⭐ **可用** | 中 | 高 | 低 | 高级查询/跨时间范围 |
| LSSharedFileList | ⚠️ **不推荐** | 高 | 中 | 高（已废弃） | 避免使用 |
| NSDocumentController | ❌ **不适用** | 低 | 低 | 低 | 仅文档类App |

---

## 10. 注意事项与最佳实践

### 10.1 权限相关

1. **读取 plist 文件不需要 TCC 授权** - 用户自己的 `~/Library/Preferences` 目录下文件可直接读取
2. **沙盒 App** 需要添加 `com.apple.security.files.user-selected.read-write` entitlement
3. **如果要用 NSMetadataQuery** 访问 Spotlight，可能需要 Full Disk Access（取决于 macOS 版本）

### 10.2 文件监视（实时更新）

如果需要监视最近目录变化，可以使用 `DispatchSource`：

```swift
import Foundation

class FinderPreferencesWatcher {
    private var source: DispatchSourceFileSystemObject?
    
    func startWatching(callback: @escaping () -> Void) {
        let path = NSHomeDirectory() + "/Library/Preferences/com.apple.finder.plist"
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        
        source?.setEventHandler {
            callback()
        }
        
        source?.setCancelHandler {
            close(fd)
        }
        
        source?.resume()
    }
    
    func stopWatching() {
        source?.cancel()
        source = nil
    }
}
```

### 10.3 边界情况处理

| 边界情况 | 处理策略 |
|----------|----------|
| plist 文件不存在 | 返回空数组，记录日志 |
| FXRecentFolders 键不存在 | 降级到 NSNavRecentPlaces |
| bookmarkData 解析失败 | 使用 fallback 路径提取 |
| 目录已被删除/移动 | 通过 validateExistence 过滤 |
| bookmark 已过期 (stale) | 仍可解析路径，但记录警告 |
| 外接卷未挂载 | 使用 `.withoutMounting` 选项避免阻塞 |
| plist 为二进制格式 | `NSDictionary(contentsOf:)` 自动处理 |

### 10.4 macOS 版本兼容性

| 数据源 | 10.13 | 10.14 | 10.15 | 11 | 12 | 13 | 14 | 15 |
|--------|-------|-------|-------|----|----|----|----|----|
| FXRecentFolders | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NSNavRecentPlaces | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️(改为NSOSPRecentPlaces) |
| LSSharedFileList | ⚠️(deprecated) | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |

### 10.5 测试命令行工具

```bash
# 查看 FXRecentFolders 原始内容
plutil -p ~/Library/Preferences/com.apple.finder.plist | grep -A 200 "FXRecentFolders"

# 查看 NSNavRecentPlaces
defaults read -g NSNavRecentPlaces 2>/dev/null || defaults read -g NSOSPRecentPlaces

# 将二进制 plist 转为 XML
plutil -convert xml1 ~/Library/Preferences/com.apple.finder.plist -o /tmp/finder.xml

# 查看 .sfl2 文件结构
plutil -p ~/Library/Application\ Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl2
```

### 10.6 关键 API 参考

| API | 框架 | 用途 |
|-----|------|------|
| `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)` | Foundation | 解析 bookmarkData |
| `URL.resourceValues(forKeys:fromBookmarkData:)` | Foundation | 不解析直接获取 bookmark 属性 |
| `NSDictionary(contentsOfFile:)` / `NSDictionary(contentsOf:)` | Foundation | 读取 plist |
| `NSDocumentController.shared.recentDocumentURLs` | AppKit | 应用级最近文档 |
| `NSMetadataQuery` | Foundation | Spotlight 查询 |
| `URL.bookmarkData(options:includingResourceValuesForKeys:relativeTo:)` | Foundation | 创建 bookmarkData |

---

## 总结

对于开发 macOS 快速目录跳转工具，**推荐的数据源优先级**如下：

1. **FXRecentFolders**（`com.apple.finder.plist`）- 主数据源
   - 已按时间排序（Item 0 最新）
   - 最多 10 条记录
   - 需要解析 bookmarkData 或 file-data
   - 无需特殊权限

2. **NSNavRecentPlaces / NSOSPRecentPlaces**（`.GlobalPreferences.plist`）- 补充数据源
   - 直接是字符串路径，无需解析
   - macOS Sequoia+ 使用 `NSOSPRecentPlaces` 键名

3. **NSMetadataQuery** - 高级备选
   - 当 plist 数据源不可用时使用
   - 性能开销较大

建议实现时同时读取 FXRecentFolders 和 NSNavRecentPlaces，合并去重后按时间排序返回。
