# Swift 核心（SpektraCore）

纯 Swift 重写 spektrafilm 的数值核心。这个 package 先在 macOS 上用 `swift test`
验证数学，之后作为 iOS App 的库引用。

## 跑起来

```bash
cd Swift
swift test                     # 单元测试
swift run spektra-probe        # 打印 profile 与 golden 数据摘要
```

Xcode 里直接 `File ▸ Open…` 选这个目录即可。

## 目录

```
Sources/SpektraCore/
  Profile.swift      胶片/相纸 profile 解码（81 波段 + 256 曲线）
  Golden.swift       读取 Reference/export_goldens.py 产出的对拍数据
  Colour.swift       RGB→XYZ 矩阵、xy 色度、三角→方形坐标
  ChromaTable.swift  192×192×3 色度表 + Mitchell 三次插值（同参考实现）
  FilmExposure.swift 阶段一：线性 RGB → 胶片 log 曝光
  Curves.swift       特性曲线（fast_interp / np.interp 两种语义）+ 3×3 矩阵
  FilmDevelopment.swift 阶段二：log 曝光 → CMY 密度（含 DIR 成色剂）
  DensityModel.swift 相纸的多层 CDF 曲线模型（阶段四用）
  PrintDevelopment.swift 阶段四：log 曝光 → 印片密度
  Printing.swift     阶段三：负片密度 → 相纸曝光（81 波段积分 + 中灰平衡）
  Scanning.swift     阶段五：印片密度 → 输出 RGB（CMF 积分 + sRGB）
  Simulation.swift   Simulator：五段串起来
  BundledPack.swift  从资源里装配好一个可渲染的胶片/相纸组合
  ImageBridge.swift  CGImage ↔ 线性 RGB（App 用）
  Resources/
    profiles/       kodak_portra_400, kodak_portra_endura
    goldens/        manifest.json + arrays.bin（输入图与各阶段中间结果）
Sources/SpektraProbe/main.swift   冒烟测试
Tests/SpektraCoreTests/           对拍测试（阶段一）与解码测试
```

## golden 数据是什么

`Reference/export_goldens.py` 用 Python 参考实现（`debug.lut_mode = True`，
关闭颗粒/光晕/自动曝光等不确定项）跑一张 24×32 的合成色块图，导出：

| 数组 | 含义 |
|---|---|
| `input.rgb` | 线性 ProPhoto 输入 |
| `taps.rgb_pre` | 预处理之后 |
| `taps.log_e_film` | 胶片曝光（log10） |
| `taps.cmy_film` | 负片青品黄密度 |
| `taps.log_e_print` | 相纸曝光（log10） |
| `taps.cmy_print` | 相纸密度 |
| `taps.rgb_out` | 最终 sRGB |
| `setup.*` | 波段、灵敏度、染料密度、曲线、tc_lut |

移植时按 tap 逐个对齐，每段都要过 `Tests/`。
