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
- 优先级队列 (用户操作优先于后台任务)
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

3. 分优先级对比（跳过 active 文件）:

   【优先级 1 - 缺失文件】立即处理：
   - CoreData 有，本地无，iCloud 有 → 下载
   - CoreData 有，本地有，iCloud 无 → 上传
     * 信任 CoreData 作为 Source of Truth
     * 不等待 iCloud 同步延迟，直接上传

   【优先级 2 - 明显冲突】快速检查：
   - 双边都有，timestamp 差异 > 2 秒：
     * macOS:
       - .notDownloaded → 优先下载
       - .downloaded/.current → timestamp 新的胜出
     * iOS: 强制刷新 metadata，再比较，timestamp 新的胜出

   【优先级 3 - 其他文件】低优先级：
   - timestamp 差异 ≤ 2 秒 → 跳过（容差范围内）
   - 双边都没有 → 标记为 missing

4. 清理孤立文件 (文件系统有但 CoreData 没有)
5. Active 文件由实时同步机制处理，DiffScan 跳过
```

**冲突解决**:
- Last-write-wins (最后写入胜出)
- 容差: 2 秒 (文件系统精度差异)
- macOS 特殊处理: `.notDownloaded` 文件优先下载，避免误覆盖

**核心价值**:
- **上传离线积压**: 用户离线期间编辑的文件，上线后需要主动上传
  - 懒加载只在用户查看文件时触发下载
  - 但上传必须主动进行，不能等用户打开文件
  - 这是 DiffScan 存在的最关键理由
- **保证最终一致性**: 作为"安全网"，确保所有文件最终都同步
  - 处理同步失败的重试（queue 失败后的恢复）
  - 处理边缘情况（崩溃、网络问题等）
- **清理孤立文件**: 删除文件系统中存在但 CoreData 中不存在的文件

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

### 3. 为什么容差 2 秒?
- **文件系统精度**: macOS/iOS 文件系统可能对 timestamp 取整
- **网络同步**: iCloud 同步可能引入亚秒级时间漂移
- **安全边界**: 避免误判

### 4. 优先级机制
**问题**: DiffScan 可能产生大量后台任务，导致用户当前编辑的文件同步操作排队很久

**方案**: 两级优先级队列
- **High Priority (默认)**: 用户触发的操作（保存、编辑 activeFile）→ 插队到队列前端
- **Normal Priority**: DiffScan 批量操作 → 添加到队列尾部

**实现**:
```swift
enum SyncPriority: Int {
    case normal = 0  // 后台 DiffScan
    case high = 1    // 用户操作
}
```

**效果**: 高优先级任务插入到第一个普通优先级任务之前，确保用户操作立即处理

### 5. 冲突检测分层
**执行层（SyncCoordinator）**:
- `uploadToCloud()` / `downloadFromCloud()` 保持"强制覆盖"语义
- 单纯执行同步操作，不做决策

**决策层（DiffScan/FileState/IOSAutoSyncModifier）**:
- DiffScan: 比较 timestamp，决定上传/下载/跳过
- FileState: 用户操作时检测冲突
- IOSAutoSyncModifier: 实时监控 active 文件变化

---

## 平台差异化处理

### Metadata 枚举策略
**macOS 端**:
- 通过 `ICloudStatusChecker` 读取每个文件的 `downloadStatus`（.notDownloaded, .downloaded, .current）
- `SyncFileState` 包含 `downloadStatus` 字段，用于判断文件是否已下载
- DiffScan 检测到 `.notDownloaded` 文件时，优先下载而不是比较 timestamp
- 避免基于不准确的本地 metadata 误覆盖云端数据

**iOS 端**:
- 在 `enumerateICloudFiles()` 时对每个文件调用 `startDownloadingUbiquitousItem()` + 100ms
- 强制 iOS 从 iCloud 拉取最新 metadata，确保 timestamp 准确
- `SyncFileState.downloadStatus` 为 nil（ICloudStatusChecker 在 iOS 上不可靠）
- DiffScan 直接比较 timestamp，因为 metadata 已在枚举时刷新

**关键原因**:
- **iOS 问题**: 占位文件的 timestamp 是缓存的，不反映 iCloud 实际状态
- **macOS 问题**: `.notDownloaded` 文件的 metadata 不准确，可能导致误覆盖
- **解决方案**: iOS 强制刷新，macOS 优先下载

---

## 潜在问题与讨论

### 1. iOS Metadata 刷新延迟
- **现状**: `startDownloadingUbiquitousItem()` + 100ms sleep
- **问题**: 100ms 是否总是够? 是否应该用 completion handler?

### 2. 冲突解决
- **现状**: Last-write-wins (自动)
- **问题**: 无用户干预，并发编辑会丢数据，是否应该检测冲突并提示用户?

### 3. DiffScan 频率
- **现状**: 仅在启动 + iCloud 恢复时
- **问题**: 如果用户直接在 iCloud Drive 修改文件? 是否需要周期性 DiffScan 或监听变化?

### 4. Active 文件跳过
- **现状**: 未实现，DiffScan 会处理所有文件
- **风险**: 可能与实时同步冲突，但影响有限（最终一致）
- **方案**: 参数传入 / 查询服务 / 弱引用（优先级：低）

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
    let priority: SyncPriority      // 优先级 (.high/.normal)
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

### SyncPriority
同步优先级：
```swift
enum SyncPriority: Int {
    case normal = 0  // 后台操作 (DiffScan)
    case high = 1    // 用户操作 (保存/编辑)
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
// 排队上传（用户操作，高优先级 - 默认）
syncCoordinator.queueUpload(fileID: "123", relativePath: "file.excalidraw")

// 排队下载（后台任务，普通优先级）
syncCoordinator.queueDownload(
    fileID: "123",
    relativePath: "file.excalidraw",
    priority: .normal
)

// 全量对比（会生成大量 .normal 优先级任务）
try await syncCoordinator.performDiffScan()

// 加载时自动同步
let data = try await syncCoordinator.loadContentWithSync(
    relativePath: "file.excalidraw",
    fileID: "123"
)
```
