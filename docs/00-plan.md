# Spektra iOS — 移植设计（v0）

> 目标：在 iPhone/iPad 上运行 spektrafilm 的完整物理管线，自用，不发布到 App Store。
> 本文只记录已经核实过的事实和可执行的决定；未定的写在 §7。

---

## 0. 一句话结论

**路线已定：纯 Swift，不引入 C++**（用户 2026-11-04 决定）。物理内核按阶段重写，
Python 参考实现作为唯一 oracle，SpektraLab 作为可运行的"规格书"与架构参考。

代价是首版更慢（内核 ~6k 行 Swift + Metal）；收益是代码库单一语言、可读、可改，
不依赖 C++/CMake/metal-cpp 这套构建链。

已经落地的地基：

- `spektrafilm/` —— 上游参考实现（commit `3bb2c2d`），`python 3.13` 虚拟环境可运行。
- `Reference/export_goldens.py` —— 导出各 tap 的 golden 数据（`Reference/goldens/`）。
- `Swift/` —— Swift Package 骨架（Profile / Golden 解码 + 冒烟测试）。
- `docs/01-stage1-spec.md` —— 第一段（`rgb → log_e_film`）的精确规格。

---

## 1. 参考实现调查（已核实）

**SpektraLab**（https://github.com/JamesQiu2005/SpektraLab，GPL-3.0，1.3.5）

| 事实 | 值 |
|---|---|
| 结构 | `modern_UI/` SwiftUI(macOS) + `engine/` C++20 + Metal，编进同一个 App |
| 引擎规模 | core 5,429 行 / pipeline 8,487 行 / shaders 1,690 行 / gpu 2,547 行 |
| 边界 | 手写 `extern "C"`（`engine/include/spektrafilm/spk_engine.h`），参数走 JSON |
| 数据 | `engine/resources/` 已烘焙：constants 9.4 MB + 28 个 profile + 8 个 print LUT |
| 精度 | 与 Python oracle 对拍：setup 227 项、render 27 配置 max 2.3e-5 |
| 性能 | M3 Max 45MP 全渲染 0.87 s；live 1600px 13 ms |
| iOS 可行性 | Metal 只用 `StorageModeShared`，无 MTLHeap / IOSurface；依赖 Metal、Accelerate(vImage)、CoreText、CoreGraphics —— iOS 全部存在 |
| 许可证 | GPL-3.0-or-later；profile 数据 CC BY-SA 4.0 |

结论：**引擎可以编到 iOS**，主要工作是构建系统与存储/内存策略，不是重写算法。

---

## 2. 路线（已选 B）

| | A. 复用 C++ 引擎（未采用） | B. 纯 Swift 重写（采用） |
|---|---|---|
| 首版可用 | 1–2 周 | 2–4 个月 |
| 代码量 | iOS 壳 + 桥接（~1.5k 行） | 物理核心 + Metal（~6k 行） |
| 保真 | 现成的 2.3e-5 | 逐阶段对拍逼近 |
| 可读性 | C++ 内核 | 全 Swift |

选择 B 的理由：用户要长期自己改这份代码（加胶片、调效果），单一语言比"Swift 壳 +
C++ 引擎"更可持续；C++ 引擎的价值被降级为**参考**（它的 `engine/src/core` 与
`pipeline.cpp` 就是逐节点的算法清单），而不是依赖。

---

## 3. 目标架构

```
SpektraIOS/
├── SpektraKit/                     Swift Package（无 UI，可在 macOS 上 swift test）
│   ├── Sources/SpektraKit/
│   │   ├── Params.swift            Codable，字段名与引擎 JSON 一一对应
│   │   ├── Renderer.swift          protocol FilmRenderer（唯一的渲染入口）
│   │   ├── Frame.swift             输入帧：linear ProPhoto float32 + 元数据
│   │   └── Engine/                 Stage A：C ABI 封装（actor，串行化 Metal 调用）
│   ├── Sources/CSpektraEngine/     C++ target（vendored engine 源码）
│   └── Tests/SpektraKitTests/      对拍测试
├── App/                            iOS App（Xcode 工程）
│   ├── SpektraApp.swift
│   ├── Import/PhotoLoader.swift    PhotosPicker + CIRAWFilter → linear ProPhoto
│   ├── Session/SessionModel.swift  @Observable 状态
│   ├── Canvas/MetalCanvas.swift    CAMetalLayer 显示 spk_result.texture
│   ├── Export/Exporter.swift       ImageIO 写 HEIF/JPEG/TIFF，Display P3
│   └── UI/                         选择器、滑块、对比
├── Resources/engine/               烘焙资源（constants + profiles + metallib）
└── Tools/
    ├── build-metallib.sh           xcrun -sdk iphoneos metal → spektrafilm.metallib
    └── sync-resources.sh
```

关键设计：**`FilmRenderer` 协议**。Stage A 的实现是 `EngineRenderer`（C++），
Stage B 的实现是 `SwiftRenderer`（纯 Swift）。界面只依赖协议，替换内核不动 UI。

---

## 4. 里程碑

| | 内容 | 验收 |
|---|---|---|
| **M0** 构建打通 | 引擎编成 iOS 静态库；metallib 用 iphoneos SDK 产出；App 显示 `spk_build_info()` | 真机启动，版本号与 math mode 正确 |
| **M1** 渲染一张图 | 内置 1MP 测试图 → `spk_open`/`spk_reprint` → 画到屏幕 | 与桌面版同参数输出一致（肉眼 + 数值） |
| **M2** 照片进/出 | 相册选图 + `CIRAWFilter` 解码；导出 HEIF 到相册 | 端到端，12MP 可导出 |
| **M3** 参数面板 | 胶片/相纸、曝光、黄/品红滤色片、颗粒开关 | 滑动可改，预览 ≤ 300 ms |
| **M4** 体感 | live tier、内存上限、Display P3 色彩管理 | 12MP 导出 < 3 s，无 OOM |
| **M5** Swift 核心 | 按 tap 阶段替换，同机 A/B | 每阶段 Δ ≤ 1e-4 |

---

## 5. 验证策略

三层，从便宜到贵：

1. **单元**：`swift test`（macOS 上跑，不用真机）——参数解析、色彩矩阵、曲线插值。
2. **对拍**：同一输入 + 同一参数，比较引擎输出与 Python oracle 的 `.npy` golden。
   引擎可按 tap 输出（`spk_export_di` 取负片、`spk_reprint` 取成品）。
3. **同机 A/B**（Stage B 专属）：App 里同时跑 `EngineRenderer` 与 `SwiftRenderer`，
   输出差值的 max/mean 直接显示在调试页。C++ 引擎就是随身 oracle，不需要 Mac 也不需要 Python。

---

## 6. 风险

| 风险 | 说明 | 对策 |
|---|---|---|
| 内存 | 12MP float32 每级 144 MB；48MP ProRAW 更狠 | 用引擎的 live/preview/full 三档；真机先测 8GB 机型 |
| 散热 | 连续导出会降频 | 一次一张，导出前 flush；不并行 |
| 构建 | metal-cpp 需要 `MTL_PRIVATE_IMPLEMENTATION`；SwiftPM 不能直接编 `.metal` | metallib 由脚本预编译成资源 |
| 签名 | 免费账号 7 天有效 | 自用可接受；或用付费账号 |
| RAW | iOS 无 LibRaw，用 `CIRAWFilter`；ProRAW DNG 支持 | 先支持 HEIF/JPEG/DNG，再评估 ProRAW |
| 许可 | 引擎 GPL-3.0，profile CC BY-SA | 仓库保持 GPL；不上架 |

---

## 7. 未定

1. Stage A 的引擎是 vendored 复制进仓库，还是 git submodule 指向 SpektraLab。
2. 首版是否需要 RAW；还是先只支持相册里的 HEIF/JPEG。

---

## 8. 进度

| 里程碑 | 状态 |
|---|---|
| M0 构建打通 | ⏳ 未在 Mac 上跑过；但类型已在 Swift 6.0.3/6.1/6.2 上远程验过 |
| M1 渲染一张图 | ✅ 五段 + `Simulator` 远程执行，对 golden 1.8e-6 |
| M2 照片进/出 | ✅ App 壳：选图、渲染、全尺寸、16-bit PNG 导出 |
| M3 参数面板 | ✅ 胶片选择、曝光、品红/黄、印相、自检 |
| M4 体感 | ✅ 多线程 + 条带；**真机耗时未知**（自检页会量） |
| M5 Metal | 未开始（设计见 `07-metal-plan.md`，等真机数据决定优先级） |

数值验收（Python 侧，逐段）：

| 段 | max abs diff |
|---|---|
| `rgb_in → log_e_film` | 6e-8 |
| `log_e_film → cmy_film` | 1.3e-7 |
| `cmy_film → log_e_print` | 8.7e-8 |
| `log_e_print → cmy_print` | 7.8e-8 |
| `cmy_print → rgb_out` | 3.0e-7 |

Swift 侧同五项在远程真编译器上跑出 **2e-7 ~ 2e-6**；`Simulator` 端到端同量级；
并行与条带相对串行/整帧 **0.0（逐位）**。阈值 2e-5。

### 尚未验证的三件事

1. `swift test` 在 Mac 上是否一次通过（类型已验，运行时未知）；
2. `ImageBridge` 的 110 行 CoreGraphics 调用（方向已修，像素格式/色彩空间靠读文档）；
3. SwiftUI 层与真机性能。
