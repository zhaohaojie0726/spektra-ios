# 阶段三规格：`cmy_film → log_e_print`

对应 `PrintingStage.expose`，关掉放大机 LUT（`use_enlarger_lut=False`）、
`print_exposure = 1`、无预闪、无扩散、无黑白场校正。

## 1. 数据

| golden | 形状 | 用途 |
|---|---|---|
| `taps.cmy_film` | (24,32,3) | 输入（负片密度） |
| `taps.log_e_print` | (24,32,3) | 期望 |
| `setup.film.channel_density` | (81,3) | 负片染料密度谱 |
| `setup.film.base_density` | (81,) | 片基密度 |
| `setup.print.log_sensitivity` | (81,3) | 相纸灵敏度（log10） |
| `setup.enlarger.base_illuminant` | (81,) | TH-KG3 灯源（已归一化） |
| `setup.enlarger.dichroic_filters` | (81,3) | 二向色滤色片透过率 |
| `setup.enlarger.cc_neutral` | (3,) | 中性滤色片包 (C, M, Y) |
| `setup.enlarger.filtered_illuminant` | (81,) | 上面三者组合的结果 |
| `setup.enlarger.density_spectral_midgray` | (81,) | 18% 灰对应的负片光谱密度 |

## 2. 步骤

**2.1 滤色后的灯源**（`DichroicFilters.apply_cc`）

```
T_f  = 10^(−CC_f/100)                       f ∈ {C, M, Y}
d_λf = 1 − (1 − filter_λf)·(1 − T_f)
I_λ  = base_λ · Π_f d_λf
```

注意 `cc_neutral` 的导出顺序就是 **(C, M, Y)** = `(0, 51.57, 52.53)`。

**2.2 负片的光谱密度**

```
D_λ = Σ_k cmy_k · channel_density_λk + base_density_λ
```

**2.3 透过 → 相纸响应**

```
light_λ = 10^(−D_λ) · I_λ         （NaN → 0）
raw_m   = Σ_λ light_λ · S_λm      （S = 10^(log_sensitivity)，NaN → 0）
```

**2.4 中灰平衡**

```
raw_mid_m  = Σ_λ 10^(−D_mid_λ) · I_λ · S_λm
g          = exp( (ln raw_mid_R + ln raw_mid_G + ln raw_mid_B) / 3 )
raw       *= 1 / g
```

⚠️ 几何平均是**跨三个通道取一个标量**（`np.mean(..., axis=2)` 在
shape (1,1,3) 上），不是每通道一个。写成每通道会让整张纸偏色。

**2.5 输出**

```
log_e_print = log10(max(raw, 0) + 1e-10)
```

## 3. 验收

`Reference/check_stage3.py`：**max abs diff 8.7e-8**。
Swift 阈值 2e-5；滤色重建单独测，阈值 1e-5。

## 4. 下一步（阶段四）

`cmy_print` 不能用 `profile.data.density_curves` 直接查表：实测差 3.2e-3，
因为参考实现走的是 `_evaluate_fitted_density(density_curves_model)`（多层
centers/amplitudes/sigmas 的解析曲线），存储的 256 点数组只是它的采样。
阶段四要先把这个模型解析出来。
