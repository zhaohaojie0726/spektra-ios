# 阶段二规格：`log_e_film → cmy_film`

对应 `develop()`，在 `debug.lut_mode = True` 下的确定性配置：颗粒关闭、
DIR 成色剂**开启**（但空间扩散关闭，`diffusion_size_um = 0`）。

## 1. 数据

| golden | 形状 | 用途 |
|---|---|---|
| `taps.log_e_film` | (24,32,3) | 输入 |
| `taps.cmy_film` | (24,32,3) | 期望输出 |
| `setup.film.log_exposure` | (256,) | 曲线横轴 −3…4 |
| `setup.film.density_curves` | (256,3) | 特性曲线 |
| `setup.couplers_matrix` | (3,3) | 已成矩阵（含 amount） |

## 2. 步骤

**2.1 归一化曲线**（`develop()` 第一行）

```
normalized[:, c] = density_curves[:, c] − nanmin(density_curves[:, c])
```

**2.2 第一次查曲线**（`fast_interp` 语义）

线性插值；`x <= xp[0]` 取 `fp[0]`，`x >= xp[-1]` 取 `fp[-1]`；
区间用 `searchsorted(side='right')`（相等时取右节点），即
`j = 第一个 xp[j] > x 的下标`，`i = j-1`。

**2.3 反解"没有成色剂时的曲线"**（每个通道一次，预处理）

```
amount_curves  = normalized @ M            # (256,3)
log_exposure_0 = log_exposure[:,None] − amount_curves
curves_0[:, c] = np.interp(log_exposure, log_exposure_0[:, c], normalized[:, c])
```

`np.interp` 与 2.2 不同：**左偏**（`side='left'`），越界取端点，
`dx == 0` 时斜率为 0。`log_exposure_0` 在 amount ≈ 1.736 以上会非单调，
届时 `np.interp` 的结果取决于 numpy 的二分查找——不要试图"修正"它
（SpektraLab trap 22 记录过）。

**2.4 每像素**

```
density  = curves(log_e)                   # 2.2
log_e_0  = log_e − M · density
out      = curves_0(log_e_0)               # 2.2
```

（没有扩散时，`compute_exposure_correction_dir_couplers` 就是点运算。）

## 3. 成色剂矩阵

由 `DirCouplersParams` 默认值构造，行=施主层、列=受主层：

```
M = diag(0.336, 0.319, 0.273)                  # gamma_samelayer_rgb
  + [[0,      0.353, 0.302],                   # R → G,B
     [0.154,  0,     0.353],                   # G → R,B
     [0.168,  0.226, 0    ]]                   # B → R,G
M *= inhibition_interlayer (1) * amount (1)
```

导出值：`[[0.336, 0.353, 0.302], [0.154, 0.319, 0.353], [0.168, 0.226, 0.273]]`。

## 4. 验收

`Reference/check_stage2.py` 实测：**max abs diff 1.3e-7**（float32 存储量化）。
Swift 阈值 2e-5，测试见 `Stage2Tests.swift`。
