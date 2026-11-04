# 接手须知（写给未来的会话或未来的你）

> 最后更新：第 31 轮。**核心已通过远程真编译器验证，平台层尚未在真机上跑过。**

## 一分钟状态

| 部分 | 状态 | 证据 |
|---|---|---|
| 五段数值核心 | ✅ 完成 | 远程真编译 + 执行，对 golden 1.8e-6 ~ 2.5e-6 |
| 并行 / 条带 | ✅ 完成 | 相对串行/整帧 **0.0（逐位）** |
| 三个胶片 pack | ✅ 完成 | Python 回放 1.7e-9；落盘后 1e-7 |
| CLI（Mac 无 Xcode） | ⏳ 未编译 | 只有语法检查 |
| iOS App（SwiftUI） | ⏳ 未编译 | 只有语法检查 |
| Metal | ⏳ 只有草稿 | `docs/12-metal-draft.md`，故意没进 target |

## 三条命令（Mac，不需要 Xcode 工程）

```bash
bash Tools/mac-first-run.sh              # build → test → probe → bench
swift run spektra-cli --bench 1024       # 有多快
swift run spektra-cli photo.heic out.png # 第一张真图
```

出错时贴 `STOPPED AT:` 之后的内容。分界点：错误在 `SpektraCore` → 核心问题；
只在 `SpektraCLI`/`App` → 平台层问题，范围小得多。

## 不要破坏的四条不变量

这些都有测试钉着，改动前先看它们为什么存在：

1. **并行与串行逐位相同** —— 管线没有空间效应，行块互不相交。
   一旦加入颗粒/光晕/模糊，这条就不成立，必须改成带 halo 的条带。
2. **条带与整帧逐位相同** —— 同上，是全尺寸导出能放进内存的前提。
3. **`max |diff| < 2e-5`** —— 五段对 golden。放宽它意味着你放弃了可验证性。
4. **Metal 必须 `-fmetal-math-mode=safe`** —— 默认 fast math 会静默漂到 1e-3。

## 仓库地图

```
Swift/Sources/SpektraCore/
  SRGB / Colour / ChromaTable      色彩基础（矩阵、LUT、传递函数）
  Curves / DensityModel            特性曲线（film 用采样、print 用 CDF 模型）
  FilmExposure / FilmDevelopment   阶段 1-2
  Printing / PrintDevelopment      阶段 3-4
  Scanning                         阶段 5
  Simulation                       把五段串起来（+ EV / 滤色 / 印相 / 条带 / 线程）
  BundledPack                      从 pack 装配 Simulator
  SelfTest                         设备上的 golden 对拍 + 计时
  ImageBridge                      CoreGraphics 边界（唯一含平台代码的核心文件）
Swift/Sources/SpektraCLI/          命令行前端
App/Sources/                       SwiftUI 壳（ContentView / SelfTestView）
Reference/                         Python 参考、烘焙、逐段对拍
Tools/                             离线检查（语法/编码/资源/远程编译与运行）
docs/00-12                         设计、逐段规格、构建、Metal、远程验证
```

## 如果继续做，按这个顺序

1. **真机/CLI 基线**（必须先做）：跑通、看图、记下 `--bench` 数字。
2. **性能决策**：Mac 上 2048² < 300 ms → Metal 不急；> 800 ms → 从
   `docs/12-metal-draft.md` 的 `printExpose` 开始。
3. **RAW**：`ImageBridge.decode` 换成 `CIRAWFilter`，其余管线不动。
4. **颗粒/光晕**：会打破不变量 1 和 2，需要重做条带（halo），是架构级改动。
5. **CAM16 输出压缩**：对应 `docs/09` 第 5 条，中等工作量。
6. **更多胶片**：`Reference/bake_packs.py` 的 `PAIRS` 加一行，重烘即可。

## 已修复的坑（别再踩）

- `SIMD3` 没有 `.dot`；矩阵要按 `Mᵀ·v` 应用（成色剂与输出矩阵都错过）。
- 色适应白点用 `_illuminant_to_xy`（SPD 积分值），不是 colour 表里的 D55。
- 相纸曲线用拟合模型（三层 CDF），不是存储的 256 点采样。
- 同空间往返矩阵不能省（差 2e-4）。
- 中灰几何平均是**跨通道一个标量**。
- 打印用负片染料 + 相纸灵敏度；扫描用相纸染料 + CMF。
- `CGImageSourceCreateImageAtIndex` 不套 EXIF 方向，要用 thumbnail API。
- 控制台里 `pow10` 必须走 `exp2`，否则 81 波段循环慢一倍以上。

详见 `docs/11-remote-check.md` 与 `docs/09-limitations.md`。
