# 阶段四规格：`log_e_print → cmy_print`

对应 `develop_print_morph`（morph 关闭时）→ `interpolate_exposure_to_density`。

与前三个阶段不同，这里**不能直接查 `profile.data.density_curves`**：那 256 个点
只是拟合模型的采样，两者最大差 **3.4e-3**，直接查表会让印片整体偏 3.2e-3。

## 1. 数据

| 来源 | 用途 |
|---|---|
| `taps.log_e_print` | 输入 |
| `taps.cmy_print` | 期望输出 |
| `profile.data.density_curves_model` | 三个通道 × 三层 CDF 的拟合模型 |
| `profile.data.log_exposure` | 256 点横轴（−3…4） |

模型 JSON 形如：

```json
{
  "model_type": "cdfs",
  "centers": [[c0, c1, c2], ...3 个通道],
  "amplitudes": [[...], ...],
  "sigmas": [[...], ...]
}
```

## 2. 曲线求值

每通道三层正态 CDF 之和：

```
z      = (x − center_i) / sigma_i
signed = −z                    （positive 胶片取反，相纸不取反）
cdf    = 0.5 · (1 + erf(signed / √2))
curve  = Σ_i amplitude_i · cdf_i
```

在 256 点横轴上求值得到 `curves[256×3]`，然后**不做归一化**（相纸曲线本来就从
某个非零密度起步，与负片不同）。

## 3. 逐像素查表

用与阶段二相同的 `fast_interp` 语义（右偏、越界 clamp）：

```
out = interp(log_e_print, curves)
```

## 4. 验收

`Reference/check_stage4.py`：

| 方案 | max abs diff |
|---|---|
| 存储的 256 点曲线查表 | 3.239e-03 |
| 归一化后再查表 | 4.061e-03 |
| **拟合模型求值后查表** | **7.806e-08** |

Swift 阈值 2e-5，测试 `Stage4Tests.swift`；另有一条测试专门断言
"模型与存储采样确实不同（> 1e-3）"，防止有人"简化"回查表。

## 5. 实现要点

- `DensityCurveModel` 从 profile JSON 解出（`Profile.densityModel`）；
- `PrintDevelopment.density` 先在 256 点轴求值一次，再逐像素插值；
- `positive` 由 `paper.info.type == "positive"` 决定，Portra Endura 是 `negative`。
