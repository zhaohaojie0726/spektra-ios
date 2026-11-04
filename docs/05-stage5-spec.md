# 阶段五规格：`cmy_print → rgb_out`

对应 `ScanningStage.scan`，关掉扫描仪 LUT、模糊、USM、glare、黑白场校正，
输出色域压缩设为 `"off"`。

## 1. 数据

| golden | 形状 |
|---|---|
| `taps.cmy_print` | (24,32,3) |
| `taps.rgb_out` | (24,32,3) |
| `setup.print.channel_density` / `base_density` | (81,3) / (81,) |
| `setup.scan.illuminant` | (81,) D50 |
| `setup.scan.cmfs` | (81,3) CIE 1931 2° |
| `setup.scan.normalization` | (1,) Σ(illum·CMF_y) |
| `setup.scan.xyz_to_rgb` | (3,3) |
| `setup.scan.roundtrip_matrix` | (3,3) |

## 2. 步骤

```
D_λ  = Σ_k cmy_k·channel_density_λk + base_density_λ
light_λ = 10^(−D_λ)·illuminant_λ            （NaN → 0）
XYZ  = Σ_λ light_λ·CMF_λ / normalization
rgb  = Mᵀ·XYZ                                （M = xyz_to_rgb）
rgb  = Rᵀ·rgb                                （同空间往返矩阵）
out  = sRGB_encode(rgb)
```

sRGB 编码：`x ≤ 0.0031308 ? 12.92x : 1.055·x^(1/2.4) − 0.055`。

## 3. 两个必须保留的细节

**3.1 矩阵朝向**：`colour.XYZ_to_RGB(np.eye(3))` 返回的矩阵**行是 XYZ**，
正确用法 `rgb = Mᵀ·XYZ`。这个和阶段一的输入矩阵是同一个约定
（`X_to_Y(eye)` 的行总是源空间）。写反了整张图偏色，但看起来仍像照片。

**3.2 同空间往返矩阵**：`colour.RGB_to_RGB(x, cs, cs, cctf_encoding=True)`
并不是"只做一次传递函数"，它内部还有一次 CAT02 色适应往返，矩阵近似单位但
非单位：

```
[[ 0.99999171,  0.00002167,  0.00000038],
 [ 0.0,         1.00004029,  0.00001192],
 [ 0.00002316, -0.00000794,  1.00000358]]
```

实测：跳过它 → 误差 **2.06e-4**；带上它 → **3.0e-7**。
SpektraLab 的 trap 7 记录的是同一件事（3.8e-4 量级）。

## 4. 验收

`Reference/check_stage5.py`：**max 3.0e-7**（带往返矩阵）。
Swift 阈值 2e-5，测试 `Stage5Tests.swift`。

## 5. 五段全部打通后的整链

```
rgb_in → log_e_film → cmy_film → log_e_print → cmy_print → rgb_out
 1e-7      6e-8         1.3e-7       8.7e-8        7.8e-8       3e-7
```

下一条命令就能一次性看到五段的误差：`swift run spektra-probe`。
