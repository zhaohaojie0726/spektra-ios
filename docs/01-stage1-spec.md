# 阶段一规格：`input.rgb → log_e_film`

目标：Swift 端对一张 24×32 的线性 ProPhoto 图，算出与 Python 完全一致的胶片
log 曝光（`taps.log_e_film`），max abs error < 1e-6。

对应的 Python 路径（`spektrafilm` @ 3bb2c2d）：

```
preprocess (identity in lut_mode)
  → filming._rgb_to_film_raw
      → _rgb_to_tc_b            colour.RGB_to_XYZ(CAT16 → D55) → xy → tri2quad
      → apply_lut_cubic_2d      Mitchell 三次插值，反射边界
      → × b
  → ×2^EV (0) → boost(0) → 无模糊/无光晕 → log10(max(x,0)+1e-10)
```

## 1. 输入与输出

| | |
|---|---|
| 输入 | `input.rgb`，shape (24,32,3)，线性 ProPhoto，float32 |
| 输出 | `taps.log_e_film`，shape (24,32,3)，log10 曝光 |
| 常量 | `setup.colour_matrix_input_to_xyz` (3×3)、`setup.tc_lut` (192,192,3) |

## 2. 步骤

**2.1 RGB → XYZ**

`setup.colour_matrix_input_to_xyz` 是行主序的 3×3，**行是 RGB、列是 XYZ**
（`colour.RGB_to_XYZ(np.eye(3))` 的返回约定），所以：

```
XYZ_i = Σ_j M[j][i] · rgb[j]        （即 XYZ = Mᵀ · rgb）
```

矩阵已经包含 RGB 原始白点 → 胶片参考光源（D55）的 CAT16 色适应，不要再乘一次。

⚠️ 这个白点是 `_illuminant_to_xy()`（光源 SPD 与 CIE 1931 CMF 积分出来的 xy），
**不是** colour 表里的 D55 `(0.33243, 0.34744)`。两者第 5 位小数就不同，会让
tc 坐标偏 3e-6、最终渲染偏 5e-5。已经烘焙进 `setup.colour_matrix_input_to_xyz`，
Swift 侧不要自己重算。

**2.2 XYZ → 色度 → 三角/方形坐标**

```
b   = X + Y + Z                     （b = max(b, 1e-10) 只用于除法）
xy  = (X/b, Y/b)                    （b = nan_to_num(b)）
s   = 1 - x
tx  = clamp(s*s, 0, 1)
ty  = clamp(y / max(s, 1e-10), 0, 1)
```

（顺序与 `_tri2quad` 一致：`x = (1-tx)^2`，`y = ty/(1-tx)`，其中 tx/ty 是 xy。）

**2.3 LUT 坐标**

```
u = tx * (N - 1)        N = 192
v = ty * (N - 1)
```

**2.4 Mitchell 三次插值（`_cubic_interp_lut_at_2d`）**

```
clamp_coordinate(c) = min(max(c, 0), N-1)
if c >= N-1: base = N-2, frac = 1
else:        base = floor(c), frac = c - base
```

权重（B = C = 1/3，`mitchell_weight`）：

```
|x| < 1:  (1/6)*((12-9B-6C)x³ + (-18+12B+6C)x² + (6-2B))
|x| < 2:  (1/6)*((-B-6C)x³ + (6B+30C)x² + (-12B-48C)x + (8B+24C))
else:     0
```

对 i,j ∈ 0..3：`wx[i] = w(frac_x + 1 - i)`，`wy[j] = w(frac_y + 1 - j)`，
索引经 `safe_index`：

```
idx < 0   → -idx
idx >= N  → 2(N-1) - idx
```

输出 = Σ (wx·wy·lut) / Σ(wx·wy)。**不要**把权重和省略掉：边界处它不等于 1。

**2.5 输出**

```
raw  = lut_value * b
logE = log10(max(raw, 0) + 1e-10)
```

## 3. 验收

实测（`Reference/check_stage1.py` 的 float32 模拟）：

| 实现 | max abs diff |
|---|---|
| float64 转写 | 6e-8 |
| float32 模拟（≈ Swift Float） | **4.8e-7** |

所以 Swift 的阈值取 **2e-5** 非常宽松，超了就是公式/索引错了，不是精度问题。
先打印最差像素的 `tc`、`b`、`raw`，再和 `check_stage1.py` 的同像素对照。

## 4. 已知的坑

- **矩阵朝向**：把 `M` 当成 `xyz = M·rgb` 会让整张图错得很"合理"（颜色偏、对比还在），
  这是最容易犯也最难看出来的一处。这个坑 SpektraLab 也记录过（trap 20）。
- `b` 的 `nan_to_num` 在除法之后；输入含 0 时 `xy` 会得到 NaN，随后 `tx/ty` 被
  `clamp` 拉回边界——Swift 里要显式把 NaN 变 0（`Float.isFinite`），因为 Swift 的
  `min/max` 会传播 NaN。
- tc_lut 已包含输入色域压缩（`input_gamut_compress`，xy 膝点 (0,1,6)），
  不要试图在 Swift 里再压缩一次。
- 这一步在 Python 是 float64；Swift 用 Float 的实测误差 4.8e-7，`2e-5` 足够。
