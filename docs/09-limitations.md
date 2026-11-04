# 已知限制（以及各自的修法）

按"对最终图像的影响"排序。每条都写明：现在是什么、为什么、怎么改。

## 1. 输入色域 → 已解决（2026-11-04）

**原来**：`ImageBridge` 把 `CGImage` 画进 sRGB 的 8-bit 上下文。iPhone 照片通常是
Display P3，转 sRGB 时超出色域的颜色在进入胶片模拟**之前**就被裁掉了。

**现在**：画进 Display P3 上下文（传递函数与 sRGB 相同，`SRGB.decode` 不变），
pack 的 `input_matrix` 按 P3 重新烘焙。sRGB 标记的文件由 Core Graphics 自动转，
两条路都对。

验证：三个 pack 重新烘焙后，Python 回放仍然 1.7e-9（内存）/ 1e-7~2e-7（float32 落盘）。

## 2. 8 bit/通道 → 已解决（2026-11-04）

**原来**：解码和输出都是 8-bit，暗部只有很少的码值，胶片曲线一放大就成阶梯。

**现在**：解码用 16-bit 上下文（`bitsPerComponent: 16` + `byteOrder16Little`），
输出也是 16-bit `CGImage`——写 PNG 时自然是 16-bit PNG。

代价是解码缓冲从 `width*height*4` 字节变成 `*8`（1600px 预览约 25 MB），可以接受。

## 3. CPU 渲染慢

**现在**：12 MP 全图在 CPU 上要几十秒到几分钟；App 只能渲染 1600 px 预览。

**原因**：两段 81 波段积分，每像素约 1,200 flop。

**修法**：Metal，先搬 `printExpose` + `scan` 两段（占 95% 时间）。
设计见 `docs/07-metal-plan.md`。

## 4. 没有颗粒、光晕、扩散

**现在**：Swift 版只实现到"干净的密度图像"。参考实现里颗粒、halation、
diffusion filter 都是空间/随机效应，尚未移植。

**影响**：目前的效果是"颜色和影调像胶片，但没有胶片质感"。

**修法**：这三者都需要空间半径，一旦加入，`docs/07-metal-plan.md` 里的
条带渲染就需要 halo（每条带多算若干像素）。颗粒还涉及 RNG 对齐——
不要追求逐像素一致，对齐统计量（RMS 粒度、功率谱）即可。

## 5. 输出色域压缩关闭

**现在**：`output_gamut_compress = "off"`，超出输出色域的像素直接裁剪。

**影响**：少量高饱和像素会硬切，而不是平滑滚降。参考实现用 CAM16-UCS 做
亮度/彩度滚降，Swift 版还没实现（CAM16 是一大块数学）。

**修法**：实现 CAM16-UCS 的 Reinhard knee（参考 `utils/gamut_compression.py`），
在 `Scanning` 之后加一段。中等工作量。

## 6. 没有 RAW

**现在**：只吃相册里的 HEIF/JPEG，且是相机 App 处理过的（已经过色调映射）。

**影响**：严格说输入不是 scene-referred 的，等于"对一张已经出片的照片再做胶片模拟"。
对自用够用，但 RAW 才是正确入口。

**修法**：`CIRAWFilter`（iOS 15+）读 DNG/ProRAW，设 `isDraftMode = false`、
输出 linear sRGB / P3，再接现有管线。约 100 行。

## 7. 只有三款胶片、一款相纸

**现在**：Portra 400 / Portra 800 / Ektar 100 × Portra Endura。

**修法**：`Reference/bake_packs.py` 的 `PAIRS` 加一行即可，单个 pack 437 KB。
参考实现有 29 个 profile，理论上都能烘。

## 8. 单线程 → 已解决（2026-11-04）

**原来**：CPU 版逐像素单线程。

**现在**：打印与扫描两段（占 95% 时间）按**行块**并行，
`Simulator.threads = 0` 表示按 CPU 核数自动切分。

安全性来自管线本身没有空间效应：每行像素独立，行块之间不共享任何状态，
也不需要 halo。远程实测 `threads: 1` 与 `threads: 4` **逐位相同**（差 0.0），
Swift 测试 `ThreadingTests` 也钉住了这一点。

（阶段一/二仍是串行：它们是查表和曲线插值，占比小，先不动。）

## 9. 照片方向 → 已解决（2026-11-04）

**原来**：用 `CGImageSourceCreateImageAtIndex` 取像素，这**不套用 EXIF 方向**——
竖拍的手机照片会横过来渲染。

**现在**：改用 `CGImageSourceCreateThumbnailAtIndex`，带两个开关：

```swift
kCGImageSourceCreateThumbnailWithTransform: true    // 按 EXIF 方向旋转
kCGImageSourceThumbnailMaxPixelSize: longEdge       // 同时缩放
```

一个调用同时解决方向和缩放，App 里也不再需要自己拿 `CGImageSource`。
