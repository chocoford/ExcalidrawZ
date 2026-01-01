# SyncCoordinator - 双向同步机制

## 模块概览

**目标**: 双向同步 Local Storage ↔ iCloud Drive
**架构**: Queue-based + Event-driven + Timestamp 冲突解决
**Source of Truth**: CoreData (File entities)

### 模块组成

```
SyncCoordinator/
├── SyncCoordinator.swift      # 主协调器 (551行) - 编排整个同步流程
├── SyncModels.swift           # 数据模型 (75行) - 定义同步事件和文件状态
├── SyncQueue.swift            # 持久化队列 (102行) - 管理待处理操作
├── FileEnumerator.swift       # 文件枚举器 (230行) - 扫描 Local/iCloud/CoreData
└── OrphanCleaner.swift        # 孤立文件清理 (128行) - 删除无主文件
```

### 支持的文件类型

| CoreData Entity | ContentType | 文件路径示例 |
|---|---|---|
| `File` | `.file` | `{fileID}.excalidraw` |
| `CollaborationFile` | `.collaborationFile` | `{fileID}.collab` |
| `FileCheckpoint` | `.checkpoint` | `{fileID}.checkpoint` |
| `MediaItem` | `.mediaItem(ext)` | `{fileID}.png/jpg/...` |

---

## 三大核心流程

### 1. Queue-based Sync (队列同步)
```
Operation → enqueue() → [500ms 防抖] → processQueue() → execute
```

**操作类型**:
- `uploadToCloud` - 上传 local → iCloud
- `downloadFromCloud` - 下载 iCloud → local
- `deleteFromCloud` / `deleteFromLocal` - 删除

**特性**:
- 持久化队列 (app 重启后恢复)
- 自动重试 (最多 3 次)
- 防抖合并 (500ms 窗口期)
- UI 状态追踪 (queued → in-progress → completed/failed)

### 2. DiffScan (全量对比)

**触发时机**:
- App 启动时
- iCloud 从不可用变为可用时

**逻辑** (以 CoreData 为准):
```
1. 枚举 CoreData 中所有应该存在的文件
2. 枚举 Local 和 iCloud 实际文件
   - macOS: 通过 ICloudStatusChecker 读取下载状态
   - iOS: 强制刷新 metadata (startDownloadingUbiquitousItem)
3. 逐个对比:
   - 双边都有:
     * macOS: 如果 iCloud 文件 .notDownloaded → 优先下载
     * 否则: timestamp 新的胜出 (容差 2 秒)
   - 仅 Local 有 → 上传到 iCloud
   - 仅 iCloud 有 → 下载到 local
   - 双边都没有 → 标记为 missing
4. 清理孤立文件 (文件系统有但 CoreData 没有)
```

**冲突解决**:
- Last-write-wins (最后写入胜出)
- 容差: 2 秒 (文件系统精度差异)
- macOS 特殊处理: `.notDownloaded` 文件优先下载，避免误覆盖

**优先级定位**:
- **非实时操作**: DiffScan 是后台全量对比，不要求实时性
- **容忍延迟**: 遇到 `.notDownloaded` 文件需要下载时，慢也没关系
- **设计目标**: 尽可能让 App 的本地数据保持最新，但不阻塞用户操作
- **对比**: 与 `loadContentWithSync` 不同，后者是打开文件时的实时同步，需要高优先级

### 3. Load with Sync (加载时同步)

**方法**: `loadContentWithSync(relativePath:fileID:)`

**逻辑**:
```
1. checkForICloudUpdate()
   - 对比 local vs iCloud timestamps
   - iOS: 强制刷新 metadata 再对比
2. 如果 iCloud 有更新 → 下载
3. 从 local 加载 (已同步)
```

**平台差异**:
- **macOS**:
  - 利用 `ICloudStatusChecker` 判断文件下载状态
  - `.current` / `.downloaded`: 直接读 timestamp（准确）
  - `.notDownloaded`: 文件未下载，需触发下载
- **iOS**:
  - `ICloudStatusChecker` 不可靠（`ubiquitousItemDownloadingStatus` 不准确）
  - 调用 `startDownloadingUbiquitousItem()` + 等待 100ms 强制刷新 metadata
  - 占位文件 timestamp 是缓存的，必须刷新

---

## iCloud 可用性监听

**流程**:
```
iCloudManager.iCloudStatusPublisher
    → handleICloudStatusChange()
    → 如果 不可用→可用: performDiffScan()
    → 如果 已经可用: processQueue()
```

**状态追踪**:
- `lastKnownICloudAvailability` - 追踪状态转换
- 只在 unavailable → available 转换时触发 DiffScan

---

## 关键设计决策

### 1. 为什么用队列?
- **防抖**: 合并快速连续的操作 (如多次保存)
- **容错**: 操作持久化,app 重启后继续
- **离线支持**: iCloud 不可用时排队,恢复后处理

### 2. 为什么用 Timestamp?
- **简单**: 不需要版本向量或 CRDT
- **够用**: 文件是二进制 blob (不是逐行合并)
- **权衡**: Last-write-wins (并发编辑会丢失)

### 3. iOS 为什么要刷新 metadata?
- **问题**: iOS iCloud Drive 用占位文件,timestamp 是缓存的
- **方案**: `startDownloadingUbiquitousItem()` 强制 iOS 从 iCloud 拉取最新 metadata
- **代价**: 每次检查延迟 100ms

### 4. 为什么容差 2 秒?
- **文件系统精度**: macOS/iOS 文件系统可能对 timestamp 取整
- **网络同步**: iCloud 同步可能引入亚秒级时间漂移
- **安全边界**: 避免误判

### 5. 为什么 SyncFileState 需要 downloadStatus?
- **macOS 问题**: `.notDownloaded` 文件 metadata 不可用
  - 如果跳过，DiffScan 会误判为"iCloud 不存在"
  - 错误地 queue upload，**覆盖云端数据**
- **解决方案**: 记录下载状态，优先下载未下载的文件
- **iOS**: `downloadStatus = nil`，改为强制刷新 metadata

---

## 潜在问题与讨论

### ⚠️ 1. 待实现：平台差异化的 Metadata 处理
- **需要实现**:
  - `SyncFileState` 添加 `downloadStatus` 字段
  - `FileEnumerator.enumerateICloudFiles()`:
    - macOS: 通过 `ICloudStatusChecker` 读取下载状态
    - iOS: 强制刷新 metadata (`startDownloadingUbiquitousItem`)
  - `DiffScan` 对比逻辑:
    - macOS: `.notDownloaded` 文件优先下载
  - `downloadFromCloud()`:
    - iOS: 读取 metadata 前先刷新
- **注意**:
  - `uploadToCloud()` 保持"强制覆盖"语义，不做冲突检测
  - 冲突检测在调用者（DiffScan/FileState）层面做

### 2. iOS Metadata 刷新延迟
- **现状**: `startDownloadingUbiquitousItem()` + 100ms sleep
- **问题**:
  - 100ms 是否总是够?
  - 是否会阻塞线程?
  - 是否应该用 completion handler?

### 3. 冲突解决
- **现状**: Last-write-wins (自动)
- **问题**:
  - 无用户干预
  - 并发编辑会丢数据
  - 是否应该检测冲突并提示用户?

### 4. DiffScan 频率
- **现状**: 仅在启动 + iCloud 恢复时
- **问题**:
  - 如果用户直接在 iCloud Drive 修改文件?
  - 是否需要周期性 DiffScan (如每 5 分钟)?
  - 是否应该监听 iCloud 文件变化 (NSMetadataQuery)?

### 5. 孤立文件清理
- **现状**: 自动静默删除
- **问题**:
  - 是否应该通知用户?
  - 是否应该移到废纸篓而非直接删除?
  - 如果 CoreData 错了,孤立文件其实是合法的呢?

### 6. 重试逻辑
- **现状**: 3 次重试后标记失败
- **问题**:
  - 失败操作在 app 重启后丢失
  - 是否应该持久化失败操作供手动重试?
  - 是否应该指数退避?

### 7. Timestamp 容差
- **现状**: 2 秒
- **问题**:
  - 2 秒是否太宽松? (可能漏掉快速编辑)
  - 2 秒是否太紧? (可能误同步)
  - 是否应该可配置?

---

## 核心数据模型

### SyncEvent
同步事件，队列中的基本单位：
```swift
struct SyncEvent {
    let id: UUID                    // 唯一标识
    let fileID: String              // 文件 ID
    let relativePath: String        // 相对路径
    let operation: SyncOperation    // 操作类型
    let timestamp: Date             // 时间戳
    let retryCount: Int             // 重试次数
}
```

### SyncOperation
同步操作类型：
```swift
enum SyncOperation {
    case uploadToCloud      // Local → iCloud
    case downloadFromCloud  // iCloud → Local
    case deleteFromCloud    // 删除 iCloud 文件
    case deleteFromLocal    // 删除 Local 文件
}
```

### SyncFileState
文件状态快照（用于 DiffScan）：
```swift
struct SyncFileState {
    let fileID: String
    let relativePath: String
    let contentType: FileStorageContentType
    let modifiedAt: Date
    let size: Int64
    let downloadStatus: DownloadStatus?  // macOS: iCloud 下载状态

    var compositeKey: String  // "{fileID}:{contentType}"

    enum DownloadStatus {
        case notDownloaded  // 文件未下载（placeholder）
        case downloaded     // 文件已下载但有云端更新
        case current        // 文件是最新的
    }
}
```

**平台差异**：
- **macOS**: `downloadStatus` 从 `ICloudStatusChecker` 获取，用于判断是否需要下载
- **iOS**: `downloadStatus = nil`（`ICloudStatusChecker` 不可靠），改为在枚举时强制刷新 metadata

---

## 组件依赖关系

### 内部组件
- **SyncQueue**: 持久化同步队列 (UserDefaults 存储)
- **FileEnumerator**: 枚举 CoreData/Local/iCloud 文件
- **OrphanCleaner**: 清理孤立文件

### 外部依赖
- **LocalStorageManager**: 本地文件 CRUD 操作
- **iCloudDriveFileManager**: iCloud Drive 操作 + 可用性监听
- **FileStatusService**: UI 状态追踪 (queued/in-progress/completed/failed)
- **PersistenceController**: CoreData 容器 (提供 context)

### 架构流程

```
┌─────────────────────────────────────────────────────────────┐
│                     SyncCoordinator (Actor)                 │
│  ┌───────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │  SyncQueue    │  │FileEnumerator│  │ OrphanCleaner   │   │
│  │ (UserDefaults)│  │              │  │                 │   │
│  └───────────────┘  └──────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌──────────────┐  ┌─────────────────┐
│ LocalStorage    │  │ iCloudDrive  │  │  CoreData       │
│ Manager         │  │ FileManager  │  │  (Source of     │
│                 │  │              │  │   Truth)        │
└─────────────────┘  └──────────────┘  └─────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│              Application Documents Directory                │
│  Local/                  iCloudDrive/         Model.sqlite  │
└─────────────────────────────────────────────────────────────┘
```

---

## 技术特性

### 1. Actor 并发模型
- **SyncCoordinator**: `actor` 类型，保证操作串行化
- **SyncQueue**: `actor` 类型，队列操作线程安全
- 避免竞态条件 (race condition)

### 2. 持久化机制
- **队列持久化**: SyncQueue 使用 UserDefaults 存储
  - Key: `com.excalidrawz.syncQueue`
  - Format: JSON 编码的 `[SyncEvent]` 数组
  - 时机: 每次 enqueue/dequeue/removeEvents 自动保存
- **恢复机制**: App 启动时自动加载队列并处理

### 3. 防抖与批处理
- **Debounce**: 500ms 窗口期合并操作
- **Batch Processing**: 快照队列一次性处理，避免迭代中修改

### 4. 错误处理
- **自动重试**: 失败操作重新入队，最多 3 次
- **失败标记**: 超过重试次数后通过 FileStatusService 标记失败
- **降级策略**: iCloud metadata 刷新失败时使用缓存数据继续

---

## 使用示例

```swift
// 排队上传
syncCoordinator.queueUpload(fileID: "123", relativePath: "file.excalidraw")

// 排队下载
syncCoordinator.queueDownload(fileID: "123", relativePath: "file.excalidraw")

// 全量对比
try await syncCoordinator.performDiffScan()

// 加载时自动同步
let data = try await syncCoordinator.loadContentWithSync(
    relativePath: "file.excalidraw",
    fileID: "123"
)
```
