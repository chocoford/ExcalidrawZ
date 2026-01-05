# DrawingSettingsPanel

用户绘图设置面板，复现 Excalidraw 的设置界面。

## 文件结构

```
DrawingSettingsPanel/
├── README.md
├── DrawingSettingsPanel.swift      # 主面板，组合所有子组件
├── ColorPicker/
│   ├── ColorPalette.swift          # Excalidraw open-color 调色板定义
│   ├── ColorButton.swift           # 颜色按钮（含透明棋盘格）
│   ├── ColorButtonGroup.swift      # 颜色按钮组（快捷颜色 + 触发按钮）
│   └── FullColorPicker.swift       # 完整颜色选择器 Popover
├── OptionButton.swift              # 通用选项按钮 + 按钮组
├── StrokeWidthPicker.swift         # 线宽选择器（可视化预览）
└── OpacitySlider.swift             # 透明度滑块
```

## 核心机制

### 1. 颜色系统
- **来源**: Excalidraw 的 [open-color](https://github.com/yeun/open-color) v1.9.1
- **Quick Picks**:
  - Stroke: `#1e1e1e` (black), `#e03131` (red[8]), `#2f9e44` (green[8]), `#1971c2` (blue[8]), `#f08c00` (yellow[8])
  - Background: `transparent`, `#ffc9c9` (red[2]), `#b2f2bb` (green[2]), `#a5d8ff` (blue[2]), `#ffec99` (yellow[2])
- **完整调色板**: 15 个颜色家族（transparent, black, white, gray, bronze, red, pink, grape, violet, blue, cyan, teal, green, yellow, orange）
- **色调**: 每个颜色家族包含 5 个色调（从浅到深）
- **透明表示**: Base64 编码的 16×16 PNG 棋盘格图案（与 Excalidraw 一致）
- **颜色选择器结构**:
  - 快捷颜色按钮（5个）
  - 分隔线（Divider）
  - 触发按钮（显示当前颜色，点击弹出 Popover）
  - Popover 内容：基础颜色网格（5列）+ 色调列表（5个）

### 2. 组件设计
- **模块化**: 每个组件独立、可复用、带 Preview
- **泛型支持**: `OptionButtonGroup<T>` 支持任意 `Equatable` 类型
- **跨平台**: macOS/iOS 通用（`PlatformImage` typealias）

### 3. 设置项
| 设置 | 类型 | 默认值 |
|------|------|--------|
| Stroke Color | Color | `#1e1e1e` |
| Background Color | Color | `transparent` |
| Fill Style | String | `hachure` / `cross-hatch` / `solid` |
| Stroke Width | Double | `1` / `2` / `4` |
| Stroke Style | String | `solid` / `dashed` / `dotted` |
| Sloppiness (Roughness) | Double | `0` / `1` / `2` |
| Edges (Roundness) | String | `sharp` / `round` |
| Opacity | Double | `0...100` |

## 使用

```swift
import SwiftUI

struct MySettingsView: View {
    @State private var settings = UserDrawingSettings()

    var body: some View {
        DrawingSettingsPanel(settings: $settings) {
            // 设置变化回调
            print("Settings updated")
        }
    }
}
```

## 数据流

```
User Interaction
    ↓
ColorButton / OptionButton / StrokeWidthPicker / OpacitySlider
    ↓
DrawingSettingsPanel (binding update)
    ↓
onSettingsChange callback
    ↓
AppPreference.customDrawingSettings (persistence)
    ↓
ExcalidrawCore.applyUserSettings() (apply to canvas)
```

## 与 Excalidraw 的一致性

- ✅ 颜色调色板（open-color）
- ✅ 快捷颜色选择（5个按钮）
- ✅ 完整颜色选择器 Popover（基础颜色网格 + 色调列表）
- ✅ 透明棋盘格图案
- ✅ 按钮样式和间距
- ✅ 选项值和默认值
- ✅ UI 布局和交互
