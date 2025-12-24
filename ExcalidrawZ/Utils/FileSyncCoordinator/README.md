# FileSyncCoordinator 设计说明（ExcalidrawZ）

本文档说明 ExcalidrawZ 中 **本地文件 + iCloud Drive 文件同步与状态监听系统** 的完整设计。

**目标不是"能同步"，而是实现接近 Finder / 文件 App / Pages 的真实用户体验。**

---

## 一、我们到底要解决什么问题

ExcalidrawZ 支持用户：
- 选择 **任意本地文件夹**
- 该文件夹 **可能位于 iCloud Drive**
- 文件可能处于以下任意状态：
  - 已完整下载到本机
  - 仅存在于云端（☁️ 占位文件）
  - 正在下载 / 上传
  - 在另一台设备上被修改
  - 存在版本冲突

我们期望的体验是：
- 文件列表能显示：
  - ☁️（未下载）
  - 下载中（进度）
  - 已完成
  - 冲突
- 远端更新能尽快被发现
- 打开文件时能自动、安全地下载
- **某一个文件状态变化，只刷新对应的 UI 行**
- 不依赖"魔法同步"，而是符合 Apple 平台真实行为

---

## 二、一个必须先接受的事实（非常重要）

**不存在一个 API 能够同时做到：**
- 枚举「用户任意选择的文件夹」
- 并且可靠地提供 iCloud 下载状态 / 下载进度 / 冲突信息

这是 Apple 平台的硬限制。

因此：

**👉 "列出文件" 和 "判断 iCloud 状态" 必须拆成两个系统**

任何试图用一个 API 一步到位的方案，都会失败。

---

## 三、Apple 提供的三类能力

### 1️⃣ 文件系统监听（Folder-level）
- **API**: FSEvents (macOS), DirectoryMonitor (iOS), NSMetadataQuery
- **擅长**: 枚举文件、监听增删改重命名
- **不能**: 判断 iCloud 状态和下载进度

### 2️⃣ iCloud 状态查询（File-level）
- **API**: `url.resourceValues(forKeys:)`, NSMetadataQuery (iCloud scope)
- **擅长**: 查询 iCloud 状态、下载进度、上传状态、冲突
- **不能**: 枚举普通文件夹

### 3️⃣ 安全读写（File-level）
- **API**: NSFileCoordinator, NSFilePresenter
- **职责**: 协调读写、避免冲突、确保版本正确

---

## 四、核心设计结论（请牢记）

```
Folder 是观察单位
File 是状态单位
UI 只关心 File
```

**这三层必须严格分离。**

---

## 五、最终架构（树状结构）

```
FileSyncCoordinator (actor, singleton)
├── 职责：对外唯一入口，协调所有子系统
├── 核心属性
│   ├── folderMonitors: [URL: FolderMonitor]
│   ├── statusRegistry: FileStatusRegistry (@MainActor)
│   │   └── boxes: [URL: FileStatusBox]
│   └── fileAccessor: SafeFileAccessor (安全文件读写)
│
├── 对外 API - 文件夹管理
│   ├── addFolder(at: URL, options: FolderSyncOptions)
│   ├── removeFolder(at: URL)
│   └── removeAllFolders()
│
├── 对外 API - 状态查询
│   ├── statusBox(for: URL) → FileStatusBox (同步访问)
│   ├── refreshStatus(for: URL)
│   └── updateFileStatus(for: URL, status: FileStatus)
│
├── 对外 API - 文件操作
│   ├── openFile(_ url: URL) async throws → Data
│   ├── saveFile(at: URL, data: Data) async throws
│   └── downloadFile(_ url: URL) async throws
│
└── 为每个文件夹创建 ──→ FolderMonitor (actor)
                        ├── 职责：单文件夹双监听架构
                        ├── folderURL: URL
                        ├── options: FolderSyncOptions
                        │
                        ├── 文件系统监听（平台特定）
                        │   ├── macOS: MacOSFileSystemMonitor (actor)
                        │   │   ├── 使用 FSEventsWrapper
                        │   │   ├── 监听 FileEvent
                        │   │   │   ├── created
                        │   │   │   ├── modified
                        │   │   │   ├── deleted
                        │   │   │   └── renamed
                        │   │   └── 回调 → FolderMonitor.onFileEvent()
                        │   │
                        │   └── iOS: IOSFileSystemMonitor (actor + NSFilePresenter)
                        │       ├── 使用 NSFilePresenter 协议
                        │       ├── 监听 FileEvent
                        │       │   ├── created
                        │       │   ├── modified
                        │       │   └── deleted
                        │       └── 回调 → FolderMonitor.onFileEvent()
                        │
                        └── iCloud 状态监听（可选，仅 iCloud 文件夹）
                            └── ICloudStatusMonitor (actor)
                                ├── 使用 NSMetadataQuery 监听文件变化事件
                                ├── 使用 ICloudStatusResolver 查询实际 iCloud 状态
                                ├── 监听的 iCloud 状态
                                │   ├── notDownloaded
                                │   ├── downloading(progress)
                                │   ├── downloaded
                                │   ├── uploading
                                │   └── conflict
                                └── 直接调用 → FileSyncCoordinator.updateFileStatus()

                                注：NSMetadataQuery 只能告诉我们"文件发生了变化"，
                                    但无法直接获取 iCloud 状态属性。
                                    ICloudStatusResolver 通过 url.resourceValues
                                    提供实际的状态查询能力。

辅助组件：
├── FileAccessor (actor)
│   ├── 职责：所有文件读写的安全协调层
│   ├── Singleton 模式 (FileAccessor.shared)
│   ├── openFile(_ url: URL) async throws → Data
│   │   ├── 检查 iCloud 状态 (ICloudStatusResolver)
│   │   ├── 自动下载（如果未下载）
│   │   ├── 使用 NSFileCoordinator 协调访问
│   │   ├── 通过 Progress.current() 追踪下载进度
│   │   ├── 实时更新 FileSyncCoordinator 状态
│   │   └── 返回文件数据
│   │
│   ├── saveFile(at: URL, data: Data) async throws
│   │   ├── 使用 NSFileCoordinator 协调写入
│   │   ├── 原子写入 (.atomic)
│   │   └── 自动处理文件冲突
│   │
│   ├── downloadFile(_ url: URL) async throws
│   │   ├── 使用 coordinatedRead 触发下载
│   │   ├── 通过 Progress.current() 获取下载进度
│   │   ├── KVO 观察进度变化
│   │   └── 实时更新状态（摒弃轮询方式）
│   │
│   ├── deleteFile(_ url: URL) async throws
│   │   ├── 使用 NSFileCoordinator 协调删除
│   │   └── 安全删除文件
│   │
│   └── coordinatedRead(url:trackProgress:) - 私有核心方法
│       ├── NSFileCoordinator.coordinate 自动触发 iCloud 下载
│       ├── Progress.current() 获取下载进度对象
│       ├── KVO 观察 fractionCompleted 变化
│       ├── 在后台线程执行，避免阻塞
│       └── 自动清理 progress observation
│
└── ICloudStatusResolver (actor)
    ├── 职责：查询文件的实际 iCloud 状态
    ├── 被 ICloudStatusMonitor 使用（必需组件）
    ├── checkStatus(for: URL) async throws → FileStatus
    │   ├── 使用 url.resourceValues(forKeys: [.ubiquitousItem...])
    │   ├── 检查是否为 iCloud 文件 (.isUbiquitousItemKey)
    │   ├── 获取下载/上传状态
    │   ├── 检测冲突
    │   └── 返回准确的 FileStatus
    └── batchCheckStatus(_ urls: [URL]) async throws → [URL: FileStatus]
        └── 并发批量查询，用于优化性能

核心数据结构：
├── FileStatusRegistry (@MainActor class)
│   ├── boxes: [URL: FileStatusBox]
│   ├── box(for: URL) → FileStatusBox
│   ├── updateStatus(for: URL, status: FileStatus)
│   └── removeBox(for: URL)
│
├── FileStatusBox (@MainActor class, ObservableObject)
│   ├── @Published var status: FileStatus
│   ├── url: URL
│   └── lastUpdated: Date
│
├── FileStatus (enum)
│   ├── loading
│   ├── local
│   ├── notDownloaded
│   ├── downloading(progress: Double?)
│   ├── downloaded
│   ├── uploading
│   ├── conflict
│   └── error(String)
│
└── FolderSyncOptions (struct)
    ├── autoCheckICloudStatus: Bool
    ├── batchCheckInterval: TimeInterval
    ├── recursive: Bool
    └── fileExtensions: [String]
```

### 数据流向

```
1. 文件系统事件流：
   用户文件操作（创建/修改/删除）
   → FileSystemMonitor 检测到变化
   → FileEvent
   → FolderMonitor.onFileEvent()
   → FileSyncCoordinator.handleFileEvent()
   → scheduleStatusCheck()（批量延迟处理）
   → FileStatusRegistry.updateStatus()
   → FileStatusBox.status 更新
   → SwiftUI 自动刷新对应行 UI

2. iCloud 状态流：
   iCloud 状态变化（下载/上传/冲突）
   → NSMetadataQuery 检测到变化
   → ICloudStatusMonitor.processMetadataItem()
   → FileStatus 映射
   → FileSyncCoordinator.updateFileStatus()
   → FileStatusRegistry.updateStatus()
   → FileStatusBox.status 更新
   → SwiftUI 自动刷新对应行 UI

3. 文件访问流：
   用户打开文件
   → FileSyncCoordinator.openFile()
   → SafeFileAccessor.openFile()
   → 检查 iCloud 状态
   → 如需下载，触发下载
   → NSFileCoordinator 协调访问
   → 返回文件数据
```

### UI 集成示例

```swift
// SwiftUI View
struct FileRowView: View {
    let fileURL: URL
    @ObservedObject var statusBox: FileStatusBox

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.statusBox = FileSyncCoordinator.shared.statusBox(for: fileURL)
    }

    var body: some View {
        HStack {
            Text(fileURL.lastPathComponent)
            Spacer()
            statusIcon
        }
        .onTapGesture {
            Task {
                do {
                    let data = try await FileSyncCoordinator.shared.openFile(fileURL)
                    // 使用文件数据
                } catch {
                    print("Failed to open file: \(error)")
                }
            }
        }
    }

    @ViewBuilder
    var statusIcon: some View {
        switch statusBox.status {
        case .notDownloaded:
            Image(systemName: "icloud")
        case .downloading(let progress):
            ProgressView(value: progress)
        case .conflict:
            Image(systemName: "exclamationmark.triangle")
        case .uploading:
            Image(systemName: "icloud.and.arrow.up")
        default:
            EmptyView()
        }
    }
}
```

---

## 六、FileSyncCoordinator 的职责

`FileSyncCoordinator` 是 **系统级协调器**，负责：
- 接受任意文件夹 URL（通用设计，不依赖 CoreData）
- 管理每个文件夹的监听上下文
- 将"文件变化"转换为"文件状态更新"
- 向 UI 提供 **稳定、低刷新成本** 的状态对象
- 协调多个子系统的生命周期

### 对外 API 设计

```swift
actor FileSyncCoordinator {
    static let shared = FileSyncCoordinator()

    // MARK: - Folder Management

    /// 注册需要监听的文件夹
    func addFolder(at url: URL, options: FolderSyncOptions) async throws

    /// 移除文件夹监听
    func removeFolder(at url: URL) async

    // MARK: - File Status Query

    /// 获取文件状态 Box（用于 SwiftUI ObservedObject）
    func statusBox(for fileURL: URL) -> FileStatusBox

    /// 强制刷新某个文件的 iCloud 状态
    func refreshStatus(for fileURL: URL) async throws

    // MARK: - File Operations

    /// 安全打开文件（自动下载 + NSFileCoordinator）
    func openFile(_ url: URL) async throws -> Data

    /// 安全保存文件
    func saveFile(at url: URL, data: Data) async throws

    /// 触发下载
    func downloadFile(_ url: URL) async throws
}
```

---

## 七、为什么「以 Folder 为入口」是必须的

- 文件是 **动态集合**
- Folder 是 **稳定边界**
- 所有系统监听 API（FSEvents / NSMetadataQuery）都是 **目录驱动**

**👉 File 级别只能作为内部状态对象，不能作为监听入口。**

---

## 八、文件级 UI 状态设计

**核心原则：Per-file ObservableObject**

每个文件一个独立的 `FileStatusBox`，避免整个 dictionary 触发全列表刷新。

```swift
/// 每个文件一个独立的 ObservableObject
@MainActor
final class FileStatusBox: ObservableObject {
    @Published var status: FileStatus
}
```

---

## 九、FileStatus 定义

```swift
enum FileStatus: Equatable {
    case loading                          // 初始状态
    case local                            // 本地文件（非 iCloud）
    case notDownloaded                    // 仅云端（☁️ 占位）
    case downloading(progress: Double?)   // 下载中
    case downloaded                       // 已下载
    case uploading                        // 上传中
    case conflict                         // 存在冲突
    case error(String)                    // 查询失败
}
```

---

## 十、FolderSyncOptions 定义

```swift
struct FolderSyncOptions {
    /// 是否自动检查 iCloud 状态（默认 true）
    var autoCheckICloudStatus: Bool = true

    /// 批量查询 iCloud 状态的间隔（秒，默认 2.0）
    var batchCheckInterval: TimeInterval = 2.0

    /// 是否递归监听子文件夹（默认 true）
    var recursive: Bool = true

    /// 文件过滤器（默认只监听 .excalidraw）
    var fileExtensions: [String] = ["excalidraw"]
}
```

---

## 十一、完整数据流

```
用户选择文件夹 (LocalFolder in CoreData)
      ↓
FileSyncCoordinator.addFolder()
      ↓
启动 FolderIndexer（FSEvents / DirectoryMonitor）
      ↓
检测到文件变化事件 (created/modified/deleted)
      ↓
更新内部文件列表
      ↓
[如果是 iCloud 文件夹]
      ↓
ICloudStatusResolver.checkStatus(url)
      ↓
url.resourceValues(forKeys: [.ubiquitousItem...])
      ↓
FileStatusRegistry.updateStatus(url, status)
      ↓
对应 FileStatusBox.status 更新
      ↓
SwiftUI 自动刷新该行 UI
```

---

## 十二、与现有架构集成

### 与 LocalFolder (CoreData) 集成

```swift
extension LocalFolder {
    /// 启动监听
    func startMonitoring(options: FolderSyncOptions = .default) async throws {
        guard let url = self.url else {
            throw FolderError.invalidFolder
        }
        try await FileSyncCoordinator.shared.addFolder(at: url, options: options)
    }

    /// 停止监听
    func stopMonitoring() async {
        guard let url = self.url else { return }
        await FileSyncCoordinator.shared.removeFolder(at: url)
    }

    /// 获取文件状态 Box
    @MainActor
    func statusBox(for fileURL: URL) -> FileStatusBox {
        FileSyncCoordinator.shared.statusBox(for: fileURL)
    }
}
```

### 在 LocalFolderMonitorModifier 中使用

```swift
struct LocalFolderMonitorModifier: ViewModifier {
    @FetchRequest var folders: FetchedResults<LocalFolder>

    func body(content: Content) -> some View {
        content
            .task {
                // 注册所有文件夹到 FileSyncCoordinator
                for folder in folders {
                    try? await folder.startMonitoring()
                }
            }
            .onDisappear {
                Task {
                    for folder in folders {
                        await folder.stopMonitoring()
                    }
                }
            }
    }
}
```

---

## 十三、下载与同步策略

| 场景 | 策略 |
|------|------|
| 打开文件 | 立即下载（使用 `NSFileCoordinator`） |
| 列表可见文件 | 小并发预取（3-5 个） |
| 不可见文件 | 只显示 ☁️，不自动下载 |
| 读写操作 | **始终使用 `NSFileCoordinator`** |
| 后台刷新 | 批量查询，避免逐个轮询 |

---

## 十四、设计优势

✅ **完全符合 Apple 平台真实行为**
✅ **可扩展**（未来接入其他云同步也不推翻）
✅ **UI 性能稳定**（单文件状态变化只刷新单行）
✅ **不依赖 undocumented 行为**
✅ **能解释所有"奇怪现象"，而不是绕开它们**
✅ **与现有 CoreData 架构无缝集成**

---

## 十五、实现优先级

### Phase 1: 核心框架
1. `FileStatusBox` + `FileStatusRegistry`
2. `FileSyncCoordinator` 基础结构
3. 与 `LocalFolder` 的集成点

### Phase 2: 文件系统监听
1. `FolderMonitor` 实现（双监听架构：FSEvents/NSFilePresenter + NSMetadataQuery）
2. 文件变化事件 → StatusBox 更新

### Phase 3: iCloud 状态查询
1. `ICloudStatusResolver` 实现
2. 批量查询优化
3. 错误处理

### Phase 4: 安全读写
1. `SafeFileAccessor` 实现
2. `NSFileCoordinator` 集成
3. 自动下载逻辑

---

## 附录：关键代码框架

### FileSyncCoordinator 骨架

```swift
actor FileSyncCoordinator {
    static let shared = FileSyncCoordinator()

    @MainActor
    private let statusRegistry = FileStatusRegistry()

    // 以 URL 为 key，不依赖 CoreData
    private var folderMonitors: [URL: FolderMonitor] = [:]

    // 接受任意文件夹 URL
    func addFolder(at url: URL, options: FolderSyncOptions) async throws

    // 移除监听
    func removeFolder(at url: URL) async

    // 获取文件状态（同步访问）
    @MainActor
    nonisolated func statusBox(for fileURL: URL) -> FileStatusBox
}
```
