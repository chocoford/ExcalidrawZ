# Migration System

## 生命周期

```
App 启动
  ↓
ContentView.onAppear
  ↓
CoreDataMigrationModifier
  ↓
1. checkMigrations() (快速检查，不阻塞)
   └── 检查: content != nil AND filePath == nil
   ↓
2. 判断分支：

   【分支A：不需要迁移】
   └── phase = .closed
       └── 用户可以正常使用 App

   【分支B：需要迁移】
   ├── phase = .waitingForSync
   ├── showMigrationSheet = true (显示等待界面)
   ├── waitForCloudKitSync() (等待 CloudKit 同步，30s超时)
   │   └── 监听 NSPersistentCloudKitContainer.eventChangedNotification
   │   └── 等待首次 import 成功
   ├── phase = .idle (等待用户确认)
   ├── 用户点击开始迁移
   ├── runPendingMigrations()
   │   ├── FileStorageManager 只保存本地（sync未启用）
   │   └── Migration 完成
   └── phase = .closed
  ↓
StartupSyncModifier 监听到 .closed
  ├── enableSync() (初始化 SyncCoordinator)
  └── performStartupSync() (DiffScan)
```

## 当前 Migrations

### 1. Extract Media Items
- **检测**：File/FileCheckpoint 的 content JSON 中有 `files` 字段
- **迁移**：提取为 MediaItem 实体，MediaItem.dataURL 保存在 CoreData

### 2. Move Content To File Storage
- **检测**：`content != nil AND filePath == nil` (File/MediaItem/FileCheckpoint/CollaborationFile)
- **迁移**：调用 FileStorageManager.saveContent() 保存到本地+iCloud，清空 CoreData 大字段

## 核心机制

### 1. Migration 与 FileStorage 的隔离

**原则**：Migration 完成前，FileStorageManager 只操作本地文件，不触发 iCloud 同步。

#### FileStorageManager

```swift
actor FileStorageManager {
    private var syncCoordinator: SyncCoordinator?
    private var isSyncEnabled = false

    // init 时不创建 SyncCoordinator
    private init() {
        self.localManager = LocalStorageManager()
        self.iCloudManager = iCloudDriveFileManager()
    }

    // Migration 完成后调用
    func enableSync() async {
        syncCoordinator = SyncCoordinator(...)
        isSyncEnabled = true
    }

    func saveContent(...) {
        // 总是保存本地
        let result = await localManager.saveContent(...)

        // 只在 sync 启用后才上传 iCloud
        if isSyncEnabled, result.wasModified {
            await syncCoordinator?.queueUpload(...)
        }
    }
}
```

**效果**：
- App 启动到 Migration 完成前：文件操作只涉及本地
- Migration 调用 saveContent() 不会触发 iCloud 同步
- 避免 SyncCoordinator 在 Migration 期间访问 CoreData

### 2. CoreDataMigrationModifier 流程优化

**改进前**（当前）：
```
waitForCloudKitSync() → checkMigrations()
用户操作到一半突然弹出迁移弹窗 ❌
```

**改进后**：
```
checkMigrations() (快速检查)
  ├── 不需要迁移 → phase = .closed (用户无感知)
  └── 需要迁移 → waitForCloudKitSync() → 显示弹窗 ✅
```

#### 实现

```swift
struct CoreDataMigrationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showMigrationSheet) { ... }
            .onAppear {
                Task { await startMigrationCheck() }
            }
    }

    private func startMigrationCheck() async {
        // 1. 先快速检查是否需要迁移
        let needsMigration = try await migrationManager.checkMigrationsNeeded(state: migrationState)

        if !needsMigration {
            // 不需要迁移，直接跳过
            migrationState.phase = .closed
            return
        }

        // 2. 需要迁移，才等待 CloudKit 同步
        if !isICloudDisabled {
            migrationState.phase = .waitingForSync
            showMigrationSheet = true
            await waitForCloudKitSync()
        }

        // 3. 显示迁移弹窗
        showMigrationSheet = true
        migrationState.phase = .idle // 等待用户确认
    }
}
```

### 3. StartupSyncModifier

```swift
struct StartupSyncModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onChange(of: migrationState.phase) { newValue in
                if newValue == .closed && !hasEnabledSync {
                    hasEnabledSync = true
                    Task {
                        // 1. 启用同步
                        await FileStorageManager.shared.enableSync()
                        // 2. DiffScan
                        try await FileStorageManager.shared.performStartupSync()
                    }
                }
            }
    }
}
```

---

## 测试检查清单

- [ ] 不需要迁移时 → 用户无感知，App 快速启动
- [ ] 需要迁移时 → 先检查，再显示弹窗
- [ ] Migration 期间保存文件 → 只存本地，不触发同步
- [ ] Migration 完成后 → enableSync() → DiffScan 上传本地文件
- [ ] App 重启（已迁移） → checkMigrations 返回 false，直接 phase = .closed
