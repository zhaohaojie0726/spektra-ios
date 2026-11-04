# Metal 草稿：`printExpose` 一个 kernel

> **状态：未编译、未运行。** 这台机器上没有 Metal 编译器，也没有 GPU。
> 这份草稿是为了让 M5 的第一步有一个具体的形状，**不要**直接放进 target——
> 放进 App 之前必须先在真机上对拍，理由见文末。

## 为什么从这一段开始

五段里，打印积分和扫描积分各占约一半时间，其余三段（查表、曲线、矩阵）
加起来不到 5%。

```
stage 1  ~5%     stage 2  ~5%     stage 3  ~45%
stage 4  ~5%     stage 5  ~45%
```

先搬 stage 3 和 stage 5，收益最大、改动面最小，而且它们的数学最"平"——
81 次循环、没有分支、没有随机数。

## 数值契约

kernel 的输出必须与 CPU 版逐像素满足：

```
max |GPU − CPU| < 1e-4
```

参考数据现成：`Swift/Sources/SpektraCore/Resources/goldens` 里的
`taps.cmy_film` 和 `taps.log_e_print`。CPU 版现在对 golden 是 2e-6，
所以 1e-4 的余量足够容纳 fp32 的累加顺序差异，又不至于把公式错误放过去。

⚠️ **不要开 fast math。** Metal 默认是 `MathModeFast`，`exp2` 与 fma 收缩
在 81 次累加里能漂到 1e-3 以上。编译 metallib 时显式加：

```
-fmetal-math-mode=safe -fmetal-math-fp32-functions=precise
```

（SpektraLab 的 `spk_math_probe` 就是为了防止这个悄悄发生。）

## MSL

```metal
#include <metal_stdlib>
using namespace metal;

// 与 PrintingExposure.logExposure 对应。每线程一个像素。
kernel void print_expose(
    texture2d<float, access::read>  negative  [[texture(0)]],   // cmy 密度, rgba32Float
    texture2d<float, access::write> result    [[texture(1)]],   // log10 曝光
    constant float *filmChannelDensity [[buffer(0)]],           // 81*3
    constant float *filmBaseDensity   [[buffer(1)]],            // 81
    constant float *paperSensitivity  [[buffer(2)]],            // 81*3
    constant float *filteredLight     [[buffer(3)]],            // 81
    constant float &gain              [[buffer(4)]],            // midgrayFactor * printExposure
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= negative.get_width() || gid.y >= negative.get_height()) return;

    float3 density = negative.read(gid).rgb;
    float3 raw = float3(0.0);

    for (int lambda = 0; lambda < 81; ++lambda) {
        int base = lambda * 3;
        float spectral =
            density.x * filmChannelDensity[base + 0] +
            density.y * filmChannelDensity[base + 1] +
            density.z * filmChannelDensity[base + 2] +
            filmBaseDensity[lambda];

        // 10^(-d) 用 exp2：与 CPU 版同一个公式，便于对拍
        float light = exp2(-spectral * 3.3219280948873623f) * filteredLight[lambda];
        if (!isfinite(light)) light = 0.0;

        raw.x += light * paperSensitivity[base + 0];
        raw.y += light * paperSensitivity[base + 1];
        raw.z += light * paperSensitivity[base + 2];
    }

    raw *= gain;
    float3 out = log10(max(raw, 0.0) + 1e-10);
    result.write(float4(out, 1.0), gid);
}
```

## 三个容易写错的地方

**1. 数组要用 `constant float *`，不是 `&`**

`constant float &x [[buffer(0)]]` 只会绑定到缓冲区的第一个 float，数组访问
`x[i]` 在 MSL 里不合法或静默取错值。数组一律用指针，单个标量才用引用。

**2. 密度是负片的，灵敏度是相纸的**

`filmChannelDensity` 必须是**胶片**的染料曲线，`paperSensitivity` 是**相纸**的
灵敏度。写混了会得到一张"自己和自己显影"的图——Python 回放时踩过，误差 0.68。

**3. `gain` 是标量**

中灰因子是跨三通道的几何平均，一个数。写成 `float3` 会让整张纸偏色。

## Swift 侧的形状

```swift
// 不进 target，先作为设计参考
final class PrintExposeKernel {
    let pipeline: MTLComputePipelineState
    let constants: MTLBuffer   // 打包 81*3 + 81 + 81*3 + 81 + 1 个 float

    func encode(commandBuffer: MTLCommandBuffer,
                negative: MTLTexture,
                result: MTLTexture,
                gain: Float)
}
```

常量打包顺序固定，和 kernel 的 buffer 索引一一对应；打包代码要与 CPU 版
共用同一份常量（`PrintingExposure.linearSensitivity` 等），避免两处各算一遍。

## 验收步骤（真机上）

1. 用 CPU 版渲染一张 1024×1024，存 `cpu.png`；
2. 用 GPU kernel 渲染同一张，存 `gpu.png`；
3. 比较：`max |diff| < 1e-4`，且差值图**没有结构性图案**
   （整片偏移 = 矩阵/归一化；条纹 = 索引或边界）。

第 3 条比第 1 条重要：一个差 3e-4 的均匀偏移通常无害，而一个差 1e-5 的
规则条纹说明索引错了。

## 为什么现在不写进 target

- 这台机器上没有 Metal 编译器，MSL 写错只会在你的 Mac 上炸，而且报错信息
  通常指向性很差；
- 一旦进 target，`swift build` 就会因为一个未验证的文件失败，把"核心能不能
  跑通"和"Metal 写得对不对"两件事绑在一起——这正是前 30 轮一直在避免的。

正确的顺序是：**CPU 版在真机上出图 → 拿到 benchmark 数字 → 再决定要不要
Metal、从哪个 kernel 开始**。
