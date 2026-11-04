# 远程真编译器验证（不需要 Mac）

这台开发机没有 Swift 工具链，但 **Compiler Explorer 有**。两条脚本把核心源码
合并成一个文件，POST 到 `godbolt.org` 真正的 Swift 编译器上：

| 脚本 | 做什么 |
|---|---|
| `Tools/typecheck-remote.py [--with-tests]` | `-typecheck`：类型检查 |
| `Tools/run-remote-tests.py` | 编译**并执行**，把 golden 数据以 base64 嵌进去，逐像素比对 |

```bash
python Tools/typecheck-remote.py --with-tests
python Tools/run-remote-tests.py
```

## 为什么走 Python 的 urllib

这台机器上 `curl` 和 `Invoke-WebRequest` 都会因为 schannel 凭证问题连不出去，
而 Python 的 OpenSSL 是通的（和 git 一样）。所以脚本用 urllib，不用 curl。

## 抓到的三个真 bug

这三处如果留到 Mac 上，就是"一编译/一跑就红"，而且前两个都长得像数据类型错误，
很难一眼看出是公式问题。

**1. `SIMD3<Float>.dot` 不存在**

```
error: value of type 'SIMD3<Float>' has no member 'dot'
```

`.dot` 是 Apple `simd` 模块的 `simd_dot` 函数，不是 `SIMD3` 的成员。改成手写点积。

**2. 成色剂矩阵用错了方向**

`np.dot(density, M)` 是 `out[m] = Σ_k density[k]·M[k][m]`——按**列**取。
Swift 里写成了按行点积（`M·d`）。矩阵不对称，所以第 2 段误差 0.258。

**3. 输出矩阵同样的问题**

`ColourMatrix` 存的是列向量再线性组合，等价于 `M·v`，而参考实现要 `Mᵀ·v`。
这一处同时影响第 1 段（输入矩阵）和第 5 段（输出矩阵）——第 5 段误差 4.0。

修完之后的实测（每次会有 2–3 倍的浮动，量级稳定）：

```
stage1 ~5e-07     stage2 ~4e-07     stage3 ~4e-07
stage4 ~7e-07     stage5 ~2e-06
threads-print 0.0     ← 1 线程 vs 4 线程，逐位相同
threads-scan  0.0
strips        0.0     ← 条带 vs 整帧，逐位相同
filter ~1e-07         ← 放大机二向色滤色模型
srgb   ~2e-07         ← sRGB 传递函数双向
simulator ~2e-06      ← `Simulator.render` 端到端（App 真正调用的入口）
```

五段全部远低于 2e-5 的验收线。`filter` 那一行补上了最后一块：前面的测试用的是
烘焙好的 `filtered_illuminant`，而 `Simulator` 是运行时用
`base_illuminant × 三片二向色滤镜` 现算的——现在这条路径也验证过了。

`simulator` 那一行是最接近真机的一次：构造 `Profile`、组装 `Simulator`、调用
`render`，走进与 App 完全相同的代码路径（含默认并行）。

## 这个方法覆盖不到什么

| 范围 | 原因 |
|---|---|
| `ImageBridge.swift` | 用 CoreGraphics/ImageIO，Linux 上没有 |
| `App/Sources/*` | SwiftUI/PhotosUI |
| SPM 资源路径（`Bundle.module`） | 远程用 `Bundle.main` 打桩 |
| 真机上的数值 | Linux 是 x86-64 + 不同 Foundation；float32 结果应一致，但未实测 |

最后一点不是问题：远程跑的是**同一份 Swift 源码、同一个 float32 语义**，
五个阶段的误差都在 1e-7 量级，与平台无关。

## 计时：远程机器不可信

驱动里带了一个计时段（同一帧串行 vs 并行），但**不要读那些数字**。同一次会话里
同一个 192×192 渲染先报 939 ms、后报 390 ms；再加一个校准循环（5000 万次浮点）
测出 **0.23 GFLOP/s**——真实 CPU 核心是 5–20 GFLOP/s，也就是说这台共享机器比真机
慢 20–80 倍，而且负载随时变化。

结论：**性能只能用设备上的数字**。App 的「自检」页里有一个 512×512 计时，
`spektra-probe` 在 Mac 上也会打印一次。把手机上的那个数乘上照片像素数，
就是真实耗时。

这也是为什么 `pow10` 从 `exp(Double)` 换成 `exp2f` 的那次改动没有带来可测收益——
不是因为它没优化，而是因为测量环境噪声远大于收益。

## 局限

godbolt 是公共服务：请求大小有限（目前 744 KB 可用）、有速率限制、数据会离开本机。
放的是公开的 spektrafilm 数据，没有隐私问题；但别把它当 CI 用——真正的 CI 是
`.github/workflows/swift.yml`（macOS runner）。
