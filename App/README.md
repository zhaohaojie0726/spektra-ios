# iOS App（SwiftUI 壳）

五个文件，都很小：

| 文件 | 作用 |
|---|---|
| `SpektraApp.swift` | `@main` |
| `Theme.swift` | 调色板与度量，照搬 SpektraLab 的 `Theme.swift` |
| `Controls.swift` | 分区头、参数行（渐变轨道）、胶片 chip |
| `ContentView.swift` | 编辑器主界面：选图 → 渲染 → 全尺寸 → 导出 |
| `SelfTestView.swift` | 自检页：设备上的 golden 对拍 + 计时 |
| （核心在 `../Swift/`） | `BundledPack` + `Simulator` |

## 布局参考 SpektraLab

桌面版是三栏（左胶片/相纸、中间画布、右参数）。手机放不下三栏，所以
**保留了它的视觉语言，把两条 rail 合成画布下方的一条**：

| SpektraLab | 这里 |
|---|---|
| 中性灰画布 + 四周深色 rail | 画布仍是中性灰，面板在下方 |
| rail 上 26 pt 的分区头（三角形 + 小号加粗标题 + 发丝线） | `SectionBlock`，同样 30 pt、同样三角 |
| 参数行：标签 / 1.36 pt 细轨 / 右对齐等宽数值 | `ScrubRow`，轨道加粗到 2 pt 便于手指 |
| 滤色片轨道用渐变表示方向（黄→蓝、品红→绿） | 相同渐变、相同语义 |
| 选中项 = 白底黑字（无圆角卡片） | 同款 `StockChip` |
| 琥珀色 `#E1A95F` 只用于状态 | 同款，仅用于进度与「通过」 |
| 小号字（9–12 pt）、等宽数字 | 同款 |

设计稿（不是截图）：[docs/mock-ios.png](../docs/mock-ios.png)，
由 `python Tools/mock-ios.py` 生成。

## 新建工程（一次，约 2 分钟）

Xcode 16：

1. **File ▸ New ▸ Project ▸ iOS ▸ App**
   - Product Name：`Spektra`
   - Interface：**SwiftUI**
   - Language：**Swift**
   - 取消 "Use Core Data"
2. 删除模板生成的 `ContentView.swift` 和 `SpektraApp.swift`（或直接覆盖）。
3. 把 `App/Sources/` 里的**五个** `.swift` 拖进工程
   （ContentView / SpektraApp / SelfTestView / Theme / Controls）。
4. **File ▸ Add Package Dependencies… ▸ Add Local…**
   选 `Swift/` 目录（`Package.swift` 所在处），把 `SpektraCore` 加到 target。
5. 选中 target ▸ General ▸ 最低部署版本 **iOS 17.0**。
6. Run（真机或模拟器）。

> 模拟器可以跑，但 Apple Silicon 上 CPU 渲染 1600px 预览大约几十秒，
> 真机会快一些。这是纯 Swift CPU 版的预期速度，Metal 化之后才是毫秒级。

## 现在能做什么

- 从相册选一张 HEIF/JPEG（解码成 **线性 Display P3**；sRGB 文件由系统自动转）
- 用内置的三个 pack 渲染（Portra 400 / Portra 800 / Ektar 100，同一款 Endura 相纸），长边缩到 1600 px
- 调曝光补偿、品红/黄滤色片位移、印相曝光，点「渲染」重出图
- 预览 + 导出 PNG
- 左上角「自检」：在设备上跑一遍五段 golden 比对，逐段显示误差与通过与否
- 右侧「试管」按钮：**不经过照片解码**，直接渲染一张程序生成的渐变图

**出问题时先按「试管」**：它绕开 `ImageBridge`（照片解码），只走
`Simulator` + SwiftUI。两者对比就能定位：

| 试管 | 照片 | 说明 |
|---|---|---|
| ✅ | ✅ | 都好 |
| ✅ | ❌ | 问题在照片解码（`ImageBridge`） |
| ❌ | — | 问题在核心或 SwiftUI |

**第一次上机先点自检。** 全绿说明这台设备上的数值和 Python 参考一致（阈值 2e-5），
比"看起来像胶片"可靠得多；有红的，把那一行的名字和误差发我。

控件语义（和桌面版不完全一样，见下）：

| 控件 | 作用 |
|---|---|
| 曝光 | 线性输入 ×2^EV。作用于**负片**，不重新平衡印相 |
| 品红 / 黄 | 放大机滤色片位移，CC 单位，直接改灯源光谱 |
| 印相 | 相纸曝光的乘数，改印相亮度 |

> 桌面版默认 `print_exposure_compensation = true`，曝光补偿会让放大机重新配光，
> 所以"调曝光不调亮度"（SpektraLab trap 30）。我们的 pack 烘焙时用的是
> `false`（与 `lut_mode` 一致），所以曝光补偿是真正的曝光变化。这是刻意选择，
> 已用参考实现验证：`EV=+1` 与"输入 ×2"逐位相同（max diff 0.0）。

## 还没做

- RAW（`CIRAWFilter`）
- 全分辨率渲染（CPU 太慢，等 Metal）
- 相册直接保存（现在是分享面板）
- 实时预览（每次改参数要手动点「渲染」，一次约十几秒）
