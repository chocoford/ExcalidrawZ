# ICloudFileKit

iCloud 文件操作核心抽象层

---

## 设计目标

提取两个系统的共享文件操作能力：
- **FileSyncCoordinator**（LocalFolder）- 用户选择的文件夹监听和状态报告
- **FileStorageManager**（CloudKit）- Core Data File entities 的文件同步

**核心理念**:
- 不依赖具体文件来源（文件系统 vs Core Data）
- 统一处理本地文件和 iCloud Drive 文件
- 提供纯粹的文件操作能力，基于 NSFileCoordinator

---

## 架构

```
ICloudFileKit (文件操作核心层)
├── ICloudFileStatus         (统一状态枚举)
├── ICloudStatusChecker      (状态查询)
├── FileCoordinator          (文件协调器 - 处理所有文件)
└── ICloudConflictResolver   (冲突解析)
          ↑
    ┌─────┴─────┐
    │           │
FileSyncCoord  FileStorage
(监听+报告)    (同步+额外操作)
```

**设计说明**:
- `FileCoordinator` 基于 NSFileCoordinator，**统一处理本地文件和 iCloud Drive 文件**
- iCloud 专属方法（如 downloadFile）内部会自动检查文件类型，本地文件调用安全
- 其他组件保留 ICloud 前缀，因为它们的概念是 iCloud 特有的

---

## 核心组件

### ICloudFileStatus

**来源**: `FileSyncCoordinator/FileStatus.swift`

统一的 iCloud 文件状态枚举：

```swift
enum ICloudFileStatus: Equatable, Sendable {
    case loading                       // 状态查询中
    case local                         // 本地文件（非 iCloud）
    case notDownloaded                 // 仅云端（☁️ placeholder）
    case downloading(progress: Double?) // 下载中
    case downloaded                    // 已下载且最新
    case outdated                      // 已下载但云端有新版本
    case uploading                     // 上传中
    case conflict                      // 有未解决的冲突
    case error(String)                 // 查询错误

    #if os(iOS)
    case syncing                       // iOS 专用：同步中
    #endif
}
```

**Helper 属性**:
- `isAvailable: Bool` - 文件是否可立即读取
- `isICloudFile: Bool` - 文件是否在 iCloud Drive
- `isInProgress: Bool` - 是否有操作进行中
- `needsUpdate: Bool` - 云端是否有更新

---

### ICloudStatusChecker

**来源**: `FileSyncCoordinator/ICloudStatusResolver.swift`

查询文件的 iCloud 状态：

```swift
actor ICloudStatusChecker {
    /// 查询单个文件状态
    func checkStatus(for url: URL) async throws -> ICloudFileStatus

    /// 批量并发查询（优化性能）
    func batchCheckStatus(_ urls: [URL]) async -> [URL: ICloudFileStatus]
}
```

**使用的 API**:
- `url.resourceValues(forKeys:)`
- URLResourceKey:
  - `.isUbiquitousItemKey` - 是否 iCloud 文件
  - `.ubiquitousItemDownloadingStatusKey` - 下载状态（notDownloaded/downloaded/current）
  - `.ubiquitousItemIsDownloadingKey` - 是否下载中
  - `.ubiquitousItemIsUploadingKey` - 是否上传中
  - `.ubiquitousItemHasUnresolvedConflictsKey` - 是否有冲突

---

### FileCoordinator

**来源**: `FileSyncCoordinator/FileAccessor.swift`

安全的文件访问协调器（NSFileCoordinator + 操作去重），**统一处理本地文件和 iCloud Drive 文件**：

```swift
actor FileCoordinator {
    // ========== 通用文件操作（对所有文件有效）==========

    /// 协调读取（自动下载 iCloud 文件 + Progress 追踪）
    func coordinatedRead<T>(
        url: URL,
        trackProgress: Bool,
        accessor: @Sendable (URL) throws -> T
    ) async throws -> T

    /// 协调写入（冲突处理）
    func coordinatedWrite(url: URL, data: Data) async throws

    /// 删除文件
    func deleteFile(url: URL) async throws

    // ========== iCloud 专属操作（会自动检查文件类型）==========

    /// 显式下载 iCloud 文件（带进度追踪）
    /// - 如果是本地文件，直接返回，不会报错
    func downloadFile(url: URL) async throws

    /// 移除 iCloud 文件的本地副本（保留云端）
    /// - 如果是本地文件，直接返回，不会报错
    func evictLocalCopy(of url: URL) async throws
}
```

**核心特性**:
- **统一处理**: 基于 NSFileCoordinator，本地文件和 iCloud 文件使用同一套 API
- **自动下载**: coordinatedRead 对 iCloud 文件会自动触发下载
- **Progress 追踪**: `Progress.current()` + KVO 监听下载进度
- **操作去重**: `ongoingOperations: [URL: Task<Data, Error>]` 防止重复下载
- **智能检查**: iCloud 专属方法会检查文件类型，本地文件调用安全

---

### ICloudConflictResolver

**来源**: `FileSyncCoordinator/ConflictResolver.swift`

解决 iCloud 文件版本冲突：

```swift
actor ICloudConflictResolver {
    init(fileURL: URL)

    /// 获取所有冲突版本
    func getConflictVersions() throws -> [FileVersion]

    /// 解决冲突（选择保留的版本）
    func resolveConflict(keepingVersion: FileVersion) throws
}

struct FileVersion: Identifiable {
    let url: URL
    let modificationDate: Date
    let deviceName: String           // 来自哪台设备
    let isCurrent: Bool              // 是否是当前版本
    var displayName: String          // UI 展示名称
}
```

**使用的 API**:
- `NSFileVersion.currentVersionOfItem(at:)` - 当前版本
- `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` - 冲突版本列表
- `NSFileVersion.removeOtherVersionsOfItem(at:)` - 清理其他版本

---

## 使用场景

### FileSyncCoordinator（LocalFolder）使用

处理用户选择的文件夹中的文件（可能是本地文件或 iCloud Drive 文件）：

```swift
// 1. 查询状态（区分本地/iCloud）
let status = try await ICloudStatusChecker.shared.checkStatus(for: fileURL)

if status.isICloudFile && !status.isAvailable {
    // 2. 下载 iCloud 文件（本地文件调用也安全，会直接返回）
    try await FileCoordinator.shared.downloadFile(url: fileURL)
}

// 3. 读取文件（无论本地还是 iCloud）
let data = try await FileCoordinator.shared.coordinatedRead(url: fileURL, trackProgress: true) { url in
    try Data(contentsOf: url)
}

// 4. 解决冲突（如果有）
if status == .conflict {
    let resolver = ICloudConflictResolver(fileURL: fileURL)
    let versions = try resolver.getConflictVersions()
    try resolver.resolveConflict(keepingVersion: selectedVersion)
}
```

---

### FileStorageManager（CloudKit）使用

处理 Core Data File entities 的文件内容（存储在 iCloud Drive App 沙盒）：

```swift
// 改造前（iCloudDriveFileManager - 不安全的直接写入）
try content.write(to: fileURL, options: .atomic)

// 改造后（使用 FileCoordinator - 协调写入）
try await FileCoordinator.shared.coordinatedWrite(url: fileURL, data: content)
```

```swift
// 改造前（手动下载 + 轮询 - 低效且不可靠）
try FileManager.default.startDownloadingUbiquitousItem(at: url)
while !FileManager.default.fileExists(atPath: url.path) {
    try await Task.sleep(nanoseconds: 100_000_000)
}

// 改造后（协调读取 - 自动下载 + 进度追踪）
let data = try await FileCoordinator.shared.coordinatedRead(url: fileURL, trackProgress: true) { url in
    try Data(contentsOf: url)
}
```

---

## 不可抽象的部分

以下部分因两个系统根本不同，**不属于 ICloudFileKit**：

- ❌ 文件监听机制（FSEvents vs CloudKit 通知）
- ❌ 文件枚举方式（FileManager.enumerator vs Core Data fetch）
- ❌ 文件内容读取（Data(contentsOf:) vs File.content + MediaItems 组装）
- ❌ 状态报告到 UI（FileSyncCoordinator.updateFileStatus vs 其他）

---

## 文件结构

```
Utils/ICloudFileKit/
├── README.md
├── ICloudFileStatus.swift          (状态枚举)
├── ICloudStatusChecker.swift       (状态查询)
├── FileCoordinator.swift           (文件协调器 - 处理所有文件)
└── ICloudConflictResolver.swift    (冲突解析)
```

---

## 设计原则

- **Actor 隔离**: 线程安全的并发操作
- **Sendable 约束**: 严格的并发安全
- **不依赖 Core Data**: 纯文件操作
- **不依赖 SwiftUI**: 可用于任何层级
- **易于测试**: 清晰的接口和职责
- **渐进式采用**: 可逐步替换现有代码
