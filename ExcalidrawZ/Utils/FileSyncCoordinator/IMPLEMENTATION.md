# FileSyncCoordinator 实现进度

## ✅ Phase 1: 核心框架 (已完成)

### 已实现的文件

1. **FileStatus.swift**
   - ✅ 定义了 8 种文件状态
   - ✅ 添加了辅助属性 (`isAvailable`, `isICloudFile`, `isInProgress`)
   - ✅ 实现了 `Equatable`

2. **FileStatusBox.swift**
   - ✅ 每个文件一个独立的 `ObservableObject`
   - ✅ 包含 `url`, `status`, `lastUpdated`
   - ✅ 实现了 `Identifiable`, `Equatable`, `Hashable`
   - ✅ `@MainActor` 隔离确保 UI 安全

3. **FileStatusRegistry.swift**
   - ✅ `@MainActor` 隔离保证 UI 安全
   - ✅ `box(for:)` - 获取或创建 FileStatusBox（同步访问）
   - ✅ `updateStatus(for:status:)` - 更新文件状态
   - ✅ `removeBox(for:)` - 移除单个文件
   - ✅ `removeBoxes(inFolder:)` - 移除文件夹内所有文件
   - ✅ `clear()` - 清空所有
   - ✅ 日志记录

4. **FolderSyncOptions.swift**
   - ✅ 完整的配置选项
   - ✅ 预设：`default`, `performance`, `localOnly`
   - ✅ 文档注释

5. **FileSyncCoordinator.swift**
   - ✅ Actor 隔离
   - ✅ Singleton 模式
   - ✅ **通用设计**：基于 URL 而非 LocalFolder（降低耦合）
   - ✅ `addFolder(at:options:)` - 注册文件夹监听（接受任意 URL）
   - ✅ `removeFolder(at:)` - 移除文件夹监听
   - ✅ `removeAllFolders()` - 移除所有监听
   - ✅ `statusBox(for:)` - 获取文件状态 Box（同步访问，`@MainActor nonisolated`）
   - ✅ `refreshStatus(for:)` - 强制刷新状态
   - ✅ `updateFileStatus(for:status:)` - 直接更新文件状态（供 ICloudStatusMonitor 调用）
   - ✅ 文件事件处理框架
   - ✅ 批量状态检查机制（延迟 2 秒合并）
   - ✅ 跨 actor 调用使用 `MainActor.run`
   - ✅ 文件夹 URL 验证（检查是否存在、是否为目录）
   - ✅ `FileEvent` 枚举（created, modified, deleted, renamed）
   - ✅ `FolderError` 错误类型（permissionDenied, folderNotFound, invalidFolder, alreadyMonitoring）
   - ✅ `folderMonitors` 使用 `[URL: FolderMonitor]` 而非 `[NSManagedObjectID: FolderMonitor]`

6. **LocalFolder+FileSyncCoordinator.swift**
   - ✅ 作为便利扩展，桥接 LocalFolder 到通用 API
   - ✅ `startMonitoring(options:)` - 提取 URL 并调用 `FileSyncCoordinator.addFolder(at:options:)`
   - ✅ `stopMonitoring()` - 提取 URL 并调用 `FileSyncCoordinator.removeFolder(at:)`
   - ✅ `statusBox(for:)` - 获取文件状态（`@MainActor`）
   - ✅ `refreshFileStatus(for:)` - 刷新文件状态

### ✅ 已解决的问题

1. **`statusBox(for:)` 同步问题** ✅
   - 将 `FileStatusRegistry` 从 `actor` 改为 `@MainActor class`
   - `statusBox(for:)` 方法标记为 `@MainActor nonisolated`
   - 可以从 SwiftUI 同步访问，无需 `await`
   - 跨 actor 调用使用 `await MainActor.run { }`

2. **通用设计重构** ✅
   - FileSyncCoordinator 现在基于 URL 而非 LocalFolder
   - 降低了与 CoreData 的耦合
   - 可以监控任意文件夹，不仅限于 LocalFolder 实体
   - LocalFolder 通过扩展方法提供便利接口
   - 更符合单一职责原则：FileSyncCoordinator 专注于文件同步，不关心数据持久化

---

## ✅ Phase 2: 文件系统监听 + iCloud 状态监听 (已完成)

### 已实现的文件

1. **FolderMonitor.swift**
   - ✅ Actor 隔离设计
   - ✅ 接受 `folderURL: URL` 和 `options: FolderSyncOptions`
   - ✅ **双监听架构**：
     - 文件系统监听（FSEvents/NSFilePresenter）
     - iCloud 状态监听（NSMetadataQuery）
   - ✅ 平台特定实现：
     - `MacOSFileSystemMonitor` (使用 FSEventsWrapper)
     - `IOSFileSystemMonitor` (使用 NSFilePresenter)
   - ✅ `ICloudStatusMonitor` (使用 NSMetadataQuery)
   - ✅ 文件扩展名过滤
   - ✅ 自动检测是否在 iCloud Drive
   - ✅ 安全范围资源访问（Security-scoped resources）

2. **MacOSFileSystemMonitor** (actor)
   - ✅ 使用 `FSEventAsyncStream` 监听文件系统事件
   - ✅ 处理文件创建、修改、删除、重命名
   - ✅ 文件类型过滤（只监听文件，不监听目录）
   - ✅ 文件扩展名过滤
   - ✅ Security-scoped resource 管理

3. **IOSFileSystemMonitor** (actor + NSFilePresenter)
   - ✅ 实现 `NSFilePresenter` 协议
   - ✅ 处理子项出现、变化、删除
   - ✅ 文件扩展名过滤
   - ✅ Security-scoped resource 管理

4. **ICloudStatusMonitor** (actor)
   - ✅ 使用 `NSMetadataQuery` 监听 iCloud 状态变化
   - ✅ 监听下载/上传状态、进度、冲突
   - ✅ 自动映射 iCloud 状态 → `FileStatus`
   - ✅ 直接更新 `FileSyncCoordinator` 的状态
   - ✅ 文件扩展名谓词过滤
   - ✅ 处理 `NSMetadataQueryDidUpdate` 和 `NSMetadataQueryDidFinishGathering`

### ✅ 已解决的问题

1. **双监听源架构** ✅
   - 文件系统监听 → `FileEvent` → `FileSyncCoordinator.handleFileEvent()`
   - iCloud 状态监听 → `FileStatus` → `FileSyncCoordinator.updateFileStatus()`
   - 两个监听源相互独立，互不干扰

2. **平台差异处理** ✅
   - macOS: 使用 FSEventsWrapper (高性能)
   - iOS: 使用 NSFilePresenter (系统推荐)
   - 统一的 `FileSystemMonitorProtocol` 抽象

3. **iCloud 状态映射** ✅
   - `NSMetadataUbiquitousItemDownloadingStatusNotDownloaded` → `.notDownloaded`
   - `NSMetadataUbiquitousItemDownloadingStatusDownloaded` → `.downloaded`
   - `NSMetadataUbiquitousItemDownloadingStatusCurrent` → `.downloaded`
   - 下载中 → `.downloading(progress: Double?)`
   - 上传中 → `.uploading`
   - 冲突 → `.conflict`

---

## ✅ Phase 3: iCloud 状态解析 (已完成)

### 已实现的组件

1. **ICloudStatusResolver.swift** ✅
   - ✅ `checkStatus(for:)` - 查询单个文件的 iCloud 状态（使用 `url.resourceValues`）
   - ✅ `batchCheckStatus(_:)` - 批量查询多个文件
   - ✅ Actor 隔离设计
   - ✅ 完整的 iCloud 状态映射：
     - `isUbiquitousItemKey` → 判断是否为 iCloud 文件
     - `ubiquitousItemDownloadingStatusKey` → 下载状态（notDownloaded, downloaded, current）
     - `ubiquitousItemIsDownloadingKey` → 是否正在下载
     - `ubiquitousItemIsUploadingKey` → 是否正在上传
     - `ubiquitousItemHasUnresolvedConflictsKey` → 是否有冲突
   - ✅ 并发批量查询支持
   - ✅ 错误处理和日志记录

### ✅ 已解决的问题

1. **NSMetadataQuery 的局限性** ✅
   - **问题**：NSMetadataQuery 只能告诉我们文件发生了变化，但无法直接获取 iCloud 状态属性
   - **解决**：ICloudStatusMonitor 使用 ICloudStatusResolver 来查询实际状态
   - **架构**：
     - NSMetadataQuery：监听文件变化事件
     - ICloudStatusResolver：查询具体的 iCloud 状态
     - 两者配合工作，实现可靠的 iCloud 状态监听

2. **状态查询的准确性** ✅
   - 使用 `url.resourceValues(forKeys:)` 获取最新的 iCloud 状态
   - 优先级处理：conflicts > uploading > downloading > downloaded/notDownloaded
   - 非 iCloud 文件返回 `.local` 状态

---

## ✅ Phase 4: 安全文件访问 (已完成)

### 已实现的组件

1. **FileAccessor.swift** ✅
   - ✅ Actor 隔离设计
   - ✅ Singleton 模式 (`FileAccessor.shared`)
   - ✅ 集成 `ICloudStatusResolver` 用于状态检查
   - ✅ `openFile(_ url: URL) async throws → Data`
     - 使用 `ICloudStatusResolver` 检查 iCloud 状态
     - 调用 `coordinatedRead` 自动下载未下载的文件
     - 实时追踪下载进度并更新状态
   - ✅ `saveFile(at: URL, data: Data) async throws`
     - 使用 `NSFileCoordinator` 协调写入
     - 原子写入 (`.atomic`) 避免数据丢失
     - 自动处理并发写入冲突
   - ✅ `downloadFile(_ url: URL) async throws`
     - 使用 `coordinatedRead` 触发下载
     - 实时追踪下载进度（`Progress.current()`）
     - 通过 KVO 观察进度变化并更新 `FileSyncCoordinator` 状态
   - ✅ `deleteFile(_ url: URL) async throws`
     - 使用 `NSFileCoordinator` 安全删除
     - 协调删除操作避免冲突
   - ✅ `coordinatedRead(url:trackProgress:)` - 核心协调读取方法
     - 使用 `NSFileCoordinator.coordinate` 自动触发 iCloud 下载
     - 通过 `Progress.current()` 获取下载进度对象
     - 使用 KVO 观察 `fractionCompleted` 实时更新进度
     - 在后台线程执行，避免阻塞主线程
     - 自动清理 progress observation

2. **FileSyncCoordinator 文件操作 API** ✅
   - ✅ `openFile(_ url: URL) async throws → Data`
   - ✅ `saveFile(at: URL, data: Data) async throws`
   - ✅ `downloadFile(_ url: URL) async throws`
   - ✅ `deleteFile(_ url: URL) async throws`
   - 所有方法委托给 `FileAccessor.shared`

### ✅ 已解决的问题

1. **iCloud 文件自动下载与进度追踪** ✅
   - 打开文件时自动检测是否需要下载
   - `NSFileCoordinator.coordinate` 自动触发下载（无需手动调用 `startDownloadingUbiquitousItem`）
   - 通过 `Progress.current()` 获取真实下载进度
   - KVO 观察进度变化，实时更新 UI 状态
   - **优势**：摒弃轮询方式，使用系统提供的原生进度追踪

2. **文件并发访问安全** ✅
   - 所有读写操作使用 `NSFileCoordinator`
   - 自动处理文件锁和访问冲突
   - 原子写入避免部分写入
   - 在后台线程执行 coordinate，避免阻塞主线程

3. **错误处理** ✅
   - 定义了 `FileAccessError` 枚举
   - 详细的错误信息和日志
   - 移除了不再需要的 `downloadTimeout` 错误

---

## 📝 下一步行动

### ✅ 已完成

1. ✅ Phase 1: 核心框架（FileStatus, FileStatusBox, FileStatusRegistry, FileSyncCoordinator）
2. ✅ Phase 2: 文件系统监听 + iCloud 状态监听（FolderMonitor, ICloudStatusMonitor）
3. ✅ Phase 3: iCloud 状态解析（ICloudStatusResolver）
4. ✅ Phase 4: 安全文件访问（FileAccessor）

### 🎯 当前阶段

- **Phase 1-4 全部完成！**
- FileSyncCoordinator 系统已完整实现

### 后续计划

1. **集成到现有代码** (优先级：高)
   - 在 `LocalFolderMonitorModifier` 中完全替换旧的监听逻辑
   - 在文件操作处使用 `FileSyncCoordinator.shared.openFile/saveFile`
   - 测试文件夹监听 → 状态更新流程
   - 验证 UI 刷新性能

2. **UI 集成** (优先级：高)
   - 在文件列表中使用 `FileStatusBox` 显示 iCloud 状态
   - 添加 iCloud 图标和下载进度指示器
   - 测试单文件状态变化是否只刷新单行

3. **测试和优化** (优先级：中)
   - 编写单元测试
   - 测试大量文件场景的性能
   - 验证 iCloud 同步的准确性

---

## 🧪 测试计划

### 单元测试
- [ ] `FileStatus` 状态转换
- [ ] `FileStatusBox` 更新逻辑
- [ ] `FileStatusRegistry` 并发安全性
- [ ] `FolderSyncOptions` 预设

### 集成测试
- [ ] 文件夹监听 → 状态更新流程
- [ ] iCloud 文件状态查询
- [ ] 批量更新性能
- [ ] 多文件夹同时监听

### UI 测试
- [ ] 单文件状态变化只刷新单行
- [ ] iCloud 图标正确显示
- [ ] 下载进度正确更新

---

## 📊 架构优势

✅ **已实现**
- 核心数据结构清晰
- Actor 隔离保证线程安全
- 单文件状态更新避免全列表刷新
- 批量处理优化性能

⏳ **待验证**
- 与现有代码的集成难度
- 性能表现（大量文件场景）
- iCloud 状态查询的准确性
