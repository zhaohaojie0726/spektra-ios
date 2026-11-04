# spektrafilm → iOS（纯 Swift 重写）

把 [spektrafilm](https://github.com/andreavolpato/spektrafilm) 的物理管线用 Swift 重写，
跑在 iPhone 上。自用项目，不发布 App Store。

**当前状态**：五段数值核心已写完，并在 Python 侧逐段验收（误差 1e-7 量级）；
三个胶片 pack 已烘焙并在 Python 侧整链回放通过（3e-7）；Swift 代码**尚未编译过**
（开发机上没有 Swift 工具链），下一步是在 Mac 上 `swift test`。

支持的组合（同一相纸 Portra Endura）：

| pack | 状态 |
|---|---|
| Kodak Portra 400 | ok |
| Kodak Portra 800 | ok |
| Kodak Ektar 100 | ok |

---

## 目录

```
spektrafilm/          上游 Python 参考实现（commit 3bb2c2d，含 .venv）
SpektraLab/           macOS 版参考实现（C++/Metal 引擎，读它的算法与坑）
Reference/            golden 导出与逐段验证脚本
Swift/                Swift Package：核心库 SpektraCore + probe + 测试
App/                  iOS App 壳（SwiftUI）
docs/                 设计、逐段规格、构建清单
Tools/                不依赖 Mac 的检查脚本
```

## 两条验证回路

**A. Python（任何机器，包括这台 Windows）**

```bash
python Tools/verify.py
```

它会重出 golden 并跑五段检查：

```
ok    stage1 rgb->log_e_film           first max 5.960e-08
ok    stage2 log_e_film->cmy_film      first max 1.318e-07
ok    stage3 cmy_film->log_e_print     first max 8.733e-08
ok    stage4 log_e_print->cmy_print    first max 7.806e-08
ok    stage5 cmy_print->rgb_out        first max 3.005e-07
```

**B. Swift（Mac）**

```bash
bash Tools/mac-first-run.sh      # build → test → probe → bench，出错会说停在哪一步
cd Swift && swift test && swift run spektra-probe
# 不用 Xcode，直接出一张图：
swift run spektra-cli photo.heic out.png
```

期望每段 `max |diff| < 2e-5`（Swift 用 Float，Python 是 Float64）。
细节与常见编译错误见 [docs/06-build.md](docs/06-build.md)。

## 五段管线

```
线性 RGB ──1──> log 曝光 ──2──> 负片密度 ──3──> 相纸曝光 ──4──> 印片密度 ──5──> 输出 RGB
```

| 段 | 对应参考实现 | Swift |
|---|---|---|
| 1 | `FilmingStage._rgb_to_film_raw` + `expose` | `FilmExposure` |
| 2 | `develop()`（曲线 + DIR 成色剂） | `FilmDevelopment` |
| 3 | `PrintingStage.expose`（81 波段积分） | `PrintingExposure` |
| 4 | `develop_print_morph`（拟合曲线模型） | `PrintDevelopment` |
| 5 | `ScanningStage.scan`（CMF 积分 + sRGB） | `Scanning` |

`Simulator` 把它们串起来，`BundledPack` 从 pack 目录装配好一个可渲染的组合：

```swift
let pack = try BundledPack.load()                       // 默认 Portra 400
let pack = try BundledPack.load(id: "kodak_ektar_100__kodak_portra_endura")
BundledPack.availableIDs()
```

## 移植中确认的几个坑

这些都不是"读代码就能看出来"的，是逐段对拍时撞出来的：

1. **矩阵朝向**：`colour.RGB_to_XYZ(eye)` 返回的矩阵行是**源空间**，
   正确用法 `XYZ = Mᵀ·rgb`。写反了图仍然像照片。
2. **色适应白点**要用光源 SPD 与 CMF 积分出来的 xy（`_illuminant_to_xy`），
   不是 colour 表里的 D55——差第 5 位小数，渲染差 5e-5。
3. **相纸曲线必须解析拟合模型**，存储的 256 点数组和模型差 3.4e-3。
4. **同空间往返矩阵**不能省：`RGB_to_RGB(cs, cs, encode=True)` 含一次 CAT02
   往返，跳过它输出差 2e-4。
5. **中灰平衡的几何平均是跨三通道取一个标量**，写成每通道会整纸偏色。
6. 中灰探针用的是 **sRGB** 解释的 0.184（与输入空间无关）——看着像 bug，
   是刻意行为。
7. **打印阶段用的是"负片的"染料曲线 + "相纸的"灵敏度**；扫描阶段才用相纸自己的
   染料曲线。写混了会得到一张"自己和自己显影"的图（误差 0.68）。

## 离线自检（不需要 Mac）

```bash
python Tools/check-syntax.py       # tree-sitter 解析 Swift 文法
python Tools/check-sources.py      # UTF-8 / BOM / 括号配对
python Tools/check-resources.py    # Swift 引用的数组名是否存在于 pack
python Tools/verify.py             # 重出 golden 并跑五段数值对拍（Python）
python Tools/typecheck-remote.py --with-tests   # 真编译器类型检查（网络）
python Tools/run-remote-tests.py                # 真编译器跑五段数值对拍（网络）
```

最后两条把核心源码（+测试）合并成一个文件，交给 godbolt.org 上真正的 Swift
编译器：一条做 `-typecheck`，一条**编译并执行**、和 golden 逐像素比对。

最近一次结果（每次略有浮动，量级不变）：

```
stage1 ~5e-07    stage2 ~4e-07    stage3 ~4e-07
stage4 ~7e-07    stage5 ~2e-06
filter ~1e-07    srgb   ~2e-07    simulator ~2e-06
```

它们揪出过三个真 bug（`SIMD3.dot` 不存在、成色剂矩阵和输出矩阵的转置方向），
详见 `docs/11-remote-check.md`。

## 下一步

1. 在 Mac 上跑 `bash Tools/mac-first-run.sh`（build → test → probe → bench）。
2. `swift run spektra-cli photo.heic out.png`，出第一张真图。
3. 建 Xcode 工程（[App/README.md](App/README.md)），装到手机，先点「自检」。
4. 拿到 benchmark 数字后再决定 Metal（草稿见 [docs/12-metal-draft.md](docs/12-metal-draft.md)）。
