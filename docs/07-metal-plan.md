# Metal 化设计（草案）

> CPU 版跑通、真机出图之后再动手。本文只定架构，不写代码——先想清楚每个
> kernel 的输入输出和精度，再写 MSL，比反过来省时间。

## 0. 为什么要 GPU

CPU 版的代价几乎全在两处 81 波段积分：

| 步骤 | 每像素运算量 |
|---|---|
| 阶段三 打印积分 | 81 × (3 乘 + 1 幂 + 3 乘加) ≈ 600 flop |
| 阶段五 扫描积分 | 同上 ≈ 600 flop |
| 其余（查表、矩阵） | < 50 flop |

12 MP 就是约 1.5×10¹⁰ flop。A17 的 fp32 峰值约 2 TFLOP/s，理论 10 ms 量级；
CPU 单线程大约 1–2 GFLOP/s，所以现在是几十秒——差三个数量级。

**目标**：1600 px 预览 < 100 ms，12 MP 全图 < 2 s（含读写）。

## 1. 数据形态

- 全程 **float32**，RGBA 打包（R,G,B,1）—— Metal 对 `rgba32Float` 的支持最稳，
  且能让一个 dispatch 的 workgroup 读写对齐。
- 81 波段常量放 **constant buffer**（不是 texture）：`film.channelDensity`(81×3)、
  `film.baseDensity`(81)、`paper.channelDensity`(81×3)、`paper.baseDensity`(81)、
  `paper.sensitivity`(81×3)、`enlarger.filtered`(81)、`scan.illuminant`(81)、
  `scan.cmfs`(81×3)。
- 曲线表与色度表放 **2D texture**（`r32Float` 或 `rgba32Float`），用硬件线性过滤：
  - `CharacteristicCurves` 256×1（三通道 → 256×3 或三张 256×1）
  - `ChromaTable` 192×192（三次插值：手动 4×4 采样，硬件只做双线性）

## 2. Kernel 划分

一次命令缓冲里顺序 dispatch，中间不读回：

| # | kernel | 输入 | 输出 |
|---|---|---|---|
| 1 | `filmExposure` | scene RGB, matrix, chroma table | log_e |
| 2 | `filmDevelop` | log_e, curves, couplers(3×3) | cmy 负片 |
| 3 | `printExpose` | cmy, film 谱常量, illum, sensitivity, midgray 因子 | log_e_print |
| 4 | `printDevelop` | log_e_print, paper 曲线 | cmy 印片 |
| 5 | `scan` | cmy, paper 谱常量, illum, CMF, 矩阵 | sRGB |

阶段二的"反解曲线"是**预处理**（256 点），在 CPU 上算一次，把结果传给 kernel 2，
不要放进逐像素路径。

## 3. 精度

- 开 `-fmetal-math-mode=safe`（不要 fast math）。SpektraLab 的 `spk_math_probe`
  就是为此存在的：fast math 下 `exp` 与 fma 收缩会漂到 1.1e-5，超过 float32 验收线。
- 幂运算用 `exp2(x * log2(10))` 或 `pow(10, x)`？前者更快且误差可预期，
  **但要先和 CPU 版对拍确认差异 < 1e-5**，别凭感觉选。
- 验收：同一张图 CPU vs GPU，`max |diff| < 1e-4`（比 CPU 黄金线的 2e-5 宽，
  因为 GPU 的 fma 收缩和寄存器精度不可控）。

## 4. 分块与内存

因为**没有空间效应**（颗粒/光晕/模糊都还没移植），每一行像素独立，
可以按条带处理：

- 条带高 256–512 行，一块 `rgba32Float` 纹理 = 4000×512×16 B ≈ 32 MB。
- 12 MP 全图：48 条带，每条带一次 dispatch 链，最后合成一张大纹理；
  或者直接渲染到一张 12 MP 纹理（`rgba32Float` = 768 MB，太大）。
- 更省的做法：条带链的最后一站直接写进 `CGImage` 的位图缓冲（懒分配），
  峰值内存 ≈ 2 个条带。

⚠️ 一旦加颗粒/光晕（有空间半径），条带之间就需要 halo，届时这条设计要改。

## 5. 与 CPU 版的关系

CPU 版**不删**。它的用途：

1. 真机上的黄金参照（同机 A/B，不需要 Mac）；
2. Metal 不可用时的回退（模拟器、老设备）；
3. 调参时的可信基线。

调试页放一个开关：`CPU / GPU / 差值可视化`。差值图是发现问题最快的方式——
数值对不上时，先看差异是"整片偏移"（矩阵/归一化）还是"局部条纹"（索引/边界）。

## 6. 顺序建议

1. 先只把 `printExpose` 和 `scan` 两个 81 波段 kernel 搬上 GPU；
   其余五段留在 CPU。这两段占 95% 的时间，改动面最小，验证最容易。
2. 用 1 MP 图对拍，达标后再搬阶段一/二。
3. 最后合并成一条命令缓冲，去掉中间读回。

这样每一步都能测，任何一步失败都能退回上一步，不会出现"整个 GPU 路径都不对，
不知道错在哪"的局面。
