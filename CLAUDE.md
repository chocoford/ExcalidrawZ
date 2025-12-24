# CLAUDE.md - AI Assistant Notes

> **规则：每次有重要发现或注意事项，更新此文件**
>
> **重要：只记录宏观大局和关键决策，不要陷入细节。细节太多等于什么都没说。**

最后更新：2025-11-17

---

## 项目概览

ExcaliDrawZ 是 Excalidraw 的原生 macOS/iOS 封装，提供文件管理、iCloud 同步、协作功能。

- **技术栈**：SwiftUI + Core Data + CloudKit + WebKit
- **代码规模**：219 个 Swift 文件，约 37,772 行
- **架构**：MVVM
- **分支**：`main` (稳定), `dev` (开发)

---

## 核心架构

### 双存储设计
```
Model.sqlite (Cloud)       - File, Group, Library, MediaItem, CollaborationFile
ExcalidrawZLocal.sqlite    - LocalFolder, LocalFileCheckpoint
```

**为什么？** 本地文件夹的安全范围书签不应同步到 iCloud。

### WebView 桥接
- 通过 WKWebView 嵌入 Excalidraw Web App
- JavaScript 消息通信（ScriptMessageHandler）
- 本地托管资源（FlyingFox）
- 资源路径：`Resources/excalidraw-latest/`（最新），`Resources/excalidraw-lagacy/`（遗留）

### 四种文件类型
```swift
enum ActiveFile {
    case file(File)                       // 数据库文件（iCloud 同步）
    case localFile(URL)                   // 本地文件系统
    case temporaryFile(URL)               // 临时文件（会话级）
    case collaborationFile(CollaborationFile)  // 协作文件
}
```

### 检查点系统
- **规则**：首次编辑创建新检查点，后续编辑更新最新检查点
- **限制**：50 个/文件，超过删除最旧的
- **存储**：数据库文件用 `FileCheckpoint`，本地文件用 `LocalFileCheckpoint`

---

## 关键注意事项

### FileState (942 行)
- 职责过重：文件 CRUD + 导入导出 + 检查点 + 协作
- 修改时务必考虑所有四种文件类型
- 考虑重构：拆分为 FileManager, CheckpointManager, CollaborationManager

### Core Data
- 使用正确的 context（viewContext = 主线程，backgroundContext = 后台）
- `@MainActor` 标注 UI 相关操作
- 批量操作用 `newBackgroundContext()`
- **类型**：Group.rank 是 `Int64`（不是 Int16）

### MediaItem 分离
- 独立存储图片/媒体，优化加载性能
- 导出时需要合并 MediaItem 内容

### iCloud 同步
- v1.6.0 修复：首次启动无网络时冻结问题
- 合并冲突策略：`NSMergeByPropertyObjectTrumpMergePolicy`
- 监听 `NSPersistentCloudKitContainer` 通知

---

## 开发规范

### 代码风格
- 异步操作用 `async/await`
- UI 类用 `@MainActor`
- 优先 `guard let` 而非强制解包
- **注释用英文**（代码会上 GitHub）


### 测试
- 运行：`Cmd+U` 或 `xcodebuild test -scheme ExcalidrawZ`
- **已覆盖**：ExcalidrawFile 模型、Core Data CRUD、文件检查点
- **未覆盖**：FileState、WebView 桥接、iCloud 同步、UI
- 测试文件：3 个（ExcalidrawFileTests, PersistenceTests, FileCheckpointTests）
- 使用内存数据库（`NSInMemoryStoreType`）
- Arrange-Act-Assert 模式
- **测试资源**：`ExcalidrawZTests/TestResources/` 存放真实 .excalidraw 文件用于测试

---

## 已知问题

### 技术债务
1. **FileState 重构** - 942 行，职责过多（优先级：中）
2. **测试覆盖率** - 仅 3/219 文件有测试（优先级：中高）
3. **遗留代码** - `excalidraw-lagacy/`、TODO 注释（优先级：低）

### 侧边栏（43 文件）
- 四大板块：Groups, Local Folders, Temporary Files, Collaboration
- 支持多选（Cmd+Click, Shift+Click）
- 拖放涉及多种文件类型转换

---

## 依赖库

**关键外部依赖：**
- ChocofordUI/Essentials - 作者自有库
- FlyingFox - 本地 HTTP 服务器
- Sparkle - 自动更新（仅非 App Store）
- MathJaxSwift - LaTeX 渲染
- FSEventsWrapper - 文件系统监听（仅 macOS）

---

## 开发检查清单

修改代码前确认：
- [ ] 理解涉及的文件类型（数据库/本地/临时/协作）
- [ ] 确认 Core Data store（Cloud/Local）
- [ ] 考虑 iCloud 同步影响
- [ ] 检查是否需要更新检查点逻辑
- [ ] 跨平台兼容性（`#if os(macOS)`）
- [ ] 主线程操作用 `@MainActor`
- [ ] 添加错误处理
- [ ] 更新此文档

---

## 变更日志

### 2025-11-17
- 创建 CLAUDE.md 并全面审查项目
- 创建 3 个测试文件（38 个测试方法，800+ 行）
- 测试改用真实 .excalidraw 文件（`TestResources/`）
- **新增 PDF Element 支持**：添加 `ExcalidrawPdfElement` 类型，包含 `fileId`, `status`, `currentPage`, `totalPages` 字段
- **新增 PDF 插入功能**：`ExcalidrawCore+PDF.swift` 提供 `loadPDF()` 方法，自动使用 PDFKit 检测页数
- **Toolbar UI**：在"More Tools"菜单中添加"Insert PDF"按钮

---

**记住：这是笔记，不是文档。只记录关键信息和"为什么"。** 🚀
