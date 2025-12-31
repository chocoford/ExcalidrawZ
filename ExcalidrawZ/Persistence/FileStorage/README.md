# FileStorageManager

Core Data File entities 的文件内容存储和同步系统

---

## 架构

```
FileStorageManager (协调层)
├── LocalStorageManager        (本地存储)
├── iCloudDriveFileManager    (iCloud Drive 存储)
└── SyncCoordinator           (同步协调)
```

---

## 职责

### FileStorageManager (对外唯一接口)

```
协调三个子系统
提供统一的存储 API
```

**核心操作**:
- `saveContent()` - 保存到本地 + 入队 iCloud 上传
- `loadContent()` - 从本地加载（可选 iCloud 版本检查）
- `deleteContent()` - 删除本地 + 入队 iCloud 删除
- `performStartupSync()` - 启动时同步（DiffScan）

### LocalStorageManager

```
位置: ~/Library/Application Support/FileStorage/
职责: 本地文件 CRUD
```

**目录结构**:
```
FileStorage/
├── Files/                  (.excalidrawz)
├── CollaborationFiles/     (.excalidrawz_collab)
├── Checkpoints/            (.excalidrawz_checkpoint)
└── MediaItems/             (images)
```

**特性**:
- 内容去重（SHA256 hash）
- 返回 `SaveResult` (path + wasModified)

### iCloudDriveFileManager

```
位置: ~/Library/Mobile Documents/iCloud~com~chocoford~excalidraw/Data/FileStorage/
职责: iCloud Drive 文件 CRUD
```

**特性**:
- 监听 iCloud 可用性
- 自动 fallback 到本地缓存
- 使用 NSFileCoordinator

### SyncCoordinator

```
职责: 本地 ↔ iCloud Drive 双向同步
依赖: iCloudDriveFileManager (使用 FileCoordinator 进行文件操作)
```

**核心机制**:

**1. DiffScan (启动时全量同步)**
```
触发时机:
  - App 启动时 (通过 FileStorageManager.performStartupSync)
  - iCloud 从不可用变为可用

流程:
  枚举本地文件 + iCloud 文件
  → 使用 composite key (fileID + contentType) 匹配
  → 时间戳对比（2秒容差）
  → 决定上传/下载/跳过
  → 批量入队同步操作
```

**2. 增量同步 (运行时)**
```
文件保存 → SyncCoordinator.queueUpload()
           → 500ms 防抖
           → 批量上传

文件加载 → SyncCoordinator.loadContentWithSync()
           → 检查 iCloud 版本
           → (如更新) 下载并更新本地
           → 读取本地文件

文件删除 → SyncCoordinator.queueCloudDelete()
           → 500ms 防抖
           → 批量删除
```

**3. 队列管理**
- **持久化**: UserDefaults 存储，应用重启后恢复
- **防抖**: 500ms 批量处理，避免频繁 I/O
- **重试**: 失败操作重试最多 3 次
- **UI 同步**: 通过 SyncStatusState 更新 UI 状态 (queued/syncing/completed/failed)
- **串行处理**: isSyncing 锁防止并发

**4. iCloud 状态监听**
```
iCloudDriveFileManager.iCloudStatusPublisher
→ 不可用 → 可用: 触发 DiffScan (发现 iCloud 独有文件)
→ 已可用: 只处理队列
```

**5. 文件匹配逻辑**
```swift
// 使用 composite key 唯一标识
compositeKey = "\(fileID):\(contentType)"

// 支持同一文件的多个版本
// 例: fileID "ABC" 可能有:
//   - ABC.excalidrawz (file)
//   - ABC.excalidrawz_checkpoint (checkpoint)
```

**设计说明**:
- 跨设备文件变化通过 DiffScan 或 loadContentWithSync 感知
- 元数据查询直接使用 FileManager（不需要 FileCoordinator）

---

## 数据流

### 保存流程

```
FileState.save()
→ FileStorageManager.saveContent()
  ├── LocalStorageManager.saveContent()
  │   └── 返回 SaveResult (path + wasModified)
  └── (如果 wasModified)
      └── SyncCoordinator.queueUpload()
          └── 500ms 防抖批量处理
              └── iCloudDriveFileManager.saveContent()
                  └── FileCoordinator.coordinatedWrite()
```

### 加载流程

```
FileState.loadContent()
→ FileStorageManager.loadContent(with fileID)
  → SyncCoordinator.loadContentWithSync()
    ├── checkForICloudUpdate()
    │   ├── 获取本地文件修改时间
    │   ├── 获取 iCloud 文件修改时间
    │   └── 对比时间戳（2秒容差）
    ├── (如果 iCloud 更新) downloadFromCloud()
    │   └── iCloudDriveFileManager.loadContent()
    │       └── FileCoordinator.coordinatedRead()
    └── LocalStorageManager.loadContent()
```

### 启动同步

**重要**：FileStorage 的同步必须等待 Migration 完成后才能启动。

```
App 启动
  ↓
ContentView.onAppear
  ↓
CoreDataMigrationModifier
  ├── checkMigrations()
  └── (如需要) runPendingMigrations()
  └── phase = .closed
  ↓
StartupSyncModifier 监听到 .closed
  ↓
1. FileStorageManager.enableSync()
   └── 初始化 SyncCoordinator
   └── 启用文件同步功能
  ↓
2. FileStorageManager.performStartupSync()
   └── SyncCoordinator.performDiffScan()
       ├── 枚举本地文件
       ├── 枚举 iCloud 文件
       ├── 时间戳对比
       └── 批量 上传/下载
```

**为什么要等待 Migration？**
- Migration 期间会调用 `FileStorageManager.saveContent()` 保存文件
- 如果 SyncCoordinator 已初始化，会触发 iCloud 同步
- 但此时 CoreData 可能处于不一致状态（content 还未迁移完）
- SyncCoordinator 的 `getValidFileIDs()` 会访问 CoreData，可能读取到错误数据

**解决方案**：
- `FileStorageManager.init()` 时不创建 SyncCoordinator
- Migration 期间文件操作只涉及本地（LocalStorageManager）
- Migration 完成后调用 `enableSync()` 初始化 SyncCoordinator
- 然后执行 `performStartupSync()` 进行首次全量同步

---

## 文件丢失处理

**问题**: CoreData 元数据存在，但实际文件（Local + iCloud）都不存在。

**机制**: 失败记录 + 被动标记

```
FailureTracker (内存)
├── 记录失败: 每次 fileNotFound 累计
├── 标记判断: 3次失败 → 视为 missing
└── 用户重试: 总是允许（不阻止任何读取）
```

**策略**:
- 用户手动打开总是重试（最高优先级）
- 失败3次后标记为 missing（不阻止访问）
- UI 查询 missing 状态显示警告
- 成功读取后自动清除失败记录

**UI 状态管理**:
```
FileStatusService (响应式状态服务 - 统一所有文件类型)
├── FileStatus (超集状态)
│   ├── contentAvailability (内容可用性)
│   ├── syncState (同步状态)
│   └── iCloudStatus (iCloud 状态)
└── FileStatusBox (一对一绑定)
    └── @Published status
```

**集成点**:
- FileStorageManager → markAvailable/markMissing (内容状态)
- SyncCoordinator → updateSyncState (同步状态)
- FileSyncCoordinator → updateICloudStatus (LocalFile iCloud 状态)
- iCloudDriveFileManager → updateICloudStatus (CoreData File iCloud 状态)

**未来扩展**（第二阶段）:
- CoreData 持久化 missing 状态

---

## 文件类型

```swift
enum FileStorageContentType {
    case file                           // .excalidrawz
    case collaborationFile              // .excalidrawz_collab
    case checkpoint                     // .excalidrawz_checkpoint
    case mediaItem(extension: String)   // images
}
```

---

## 同步策略

| 场景 | 策略 |
|------|------|
| 保存文件 | 立即保存本地 → 500ms 防抖后批量上传 iCloud |
| 加载文件 | 检查 iCloud 版本 → 如更新则下载 → 读本地 |
| 删除文件 | 立即删本地 → 入队 iCloud 删除 |
| App 启动 | DiffScan：时间戳对比 → 双向同步 |
| iCloud 不可用 | 降级到本地存储 |
| iCloud 恢复可用 | 触发 DiffScan → 发现并下载 iCloud 独有文件 |

---

## 与 Core Data 的关系

```
Core Data File
├── id: UUID
├── name: String
├── content: Data? (废弃，迁移到 FileStorage)
└── contentPath: String (新增，指向 FileStorage)

FileStorage 存储实际文件内容
Core Data 只存储元数据
```

---

## 文件结构

```
Persistence/FileStorage/
├── README.md
├── FileStorageManager.swift          (协调层)
├── FileStorageTypes.swift            (共享类型)
├── LocalStorageManager.swift         (本地存储)
└── SyncCoordinator.swift             (同步协调)

Persistence/iCloudDrive/
├── iCloudDriveFileManager.swift      (iCloud 存储)
├── File+iCloudDrive.swift            (Core Data 扩展)
├── CollaborationFile+iCloudDrive.swift
├── FileCheckpoint+iCloudDrive.swift
└── MediaItem+iCloudDrive.swift
```
