# 交付包与 Mac 上要做的事

## 1. 包里有什么

`dist/spektra-ios-mac-<日期>.zip`（约 2.3 MB，解压 3.4 MB）：

| 目录 | 内容 |
|---|---|
| `Swift/` | Swift Package：核心库、probe、9 个测试文件、烘焙数据（golden + 4 个 profile + 3 个 pack） |
| `App/` | iOS App 源码（3 个文件）+ 建工程说明 |
| `docs/` | 设计、逐段规格、构建清单、Metal 计划 |
| `Tools/` | 四个离线检查脚本 + 打包脚本 |
| `Reference/` | 烘焙与对拍脚本（**Mac 上不需要**，除非要新增胶片） |
| `README.md` | 项目门面 |

**没有**：Python 参考仓库、虚拟环境、uv 缓存、SpektraLab。Swift 包自带全部数据，
Mac 上装好 Xcode 就能 `swift build`，**不需要 Python**。

内置三款胶片：Portra 400 / Portra 800 / Ektar 100（同一款 Endura 相纸）。

## 2. 怎么传过去

任选其一：

**A. AirDrop / U 盘（最省事）**

直接把 `dist/spektra-ios-mac-<日期>.zip` 拖过去。AirDrop 和 U 盘不会打上
quarantine 标记，省掉第 3 步的一个命令。

**B. 网盘 / 浏览器下载**

下载后 macOS 会给文件打 quarantine 标记，解压前先清掉：

```bash
xattr -dr com.apple.quarantine spektra-ios-mac-20261104.zip
```

**C. Git（如果你想长期迭代）**

在 Windows 上：

```bash
cd "F:\桌面\spektraflim to ios"
git init && git add Swift App docs Tools README.md .github
git commit -m "spektrafilm iOS: core + packs + app shell"
git remote add origin <你的私有仓库>
git push -u origin main
```

Mac 上 `git clone` 即可。**注意**：`Swift/Sources/SpektraCore/Resources/packs/`
里有 3 个 437 KB 的二进制文件，Git 能处理，但别频繁重烘。

**C+：不想坐在 Mac 前面也能拿到编译错误**

仓库里带了 `.github/workflows/swift.yml`。推到 GitHub 之后，每次 push 都会在
`macos-14` 上跑 `swift build` + `swift test`，日志里就是本机 `swift build`
会打印的东西。第一次跑完把失败的步骤日志贴给我即可——不用打开 Xcode，
也不用装任何东西。

## 3. 解压后先校验

```bash
shasum -a 256 spektra-ios-mac-20261104.zip
# 对照同目录的 .sha256 文件
unzip spektra-ios-mac-20261104.zip -d spektra-ios
cd spektra-ios
```

## 4. Mac 上按顺序做

### 第 1 步：环境

```bash
swift --version        # 需要 Swift 5.9+（Xcode 16 自带 6.x，兼容）
xcodebuild -version    # 需要 Xcode 16+
sw_vers                # 需要 macOS 14+
```

### 第 2 步：编译核心（不用 Xcode 工程）

```bash
cd Swift
swift build
```

第一次约 1 分钟（约 1,400 行，无第三方依赖）。这一步只验证"能不能编译"。

### 第 3 步：跑测试

```bash
swift test
```

预期约 30 个测试全绿，并且跟数值有关的测试会打印自己那段的误差：

```
stage1 max |diff| = ..., mean = ..., worst index ...
stage2 max |diff| = ...
end-to-end max |diff| = ...
```

**判据**：`max |diff| < 2e-5`。

### 第 4 步：整链快速看一眼

```bash
swift run spektra-probe
```

打印 profile 摘要 + 五段误差，一眼能看出哪段不对。

### 第 5 步：建 iOS 工程

见 `App/README.md`，六步：New Project ▸ iOS App ▸ SwiftUI ▸ 拖入 3 个源文件
▸ Add Local Package（选 `Swift/`）▸ 部署目标 iOS 17 ▸ Run。

免费 Apple ID 也能上真机（签名 7 天有效，到期重签）。

### 第 6 步：真机出第一张图

相册选一张 HEIF，等十几秒（CPU 渲染 1600 px 预览），看结果，右上角导出。

## 5. 出错时给我什么

只贴**前 3 条**错误——Swift 的报错会连锁，后面的基本是噪音。

另外附：

```bash
swift --version
xcodebuild -version
```

`docs/06-build.md` 里有按概率排序的 7 类常见错误（Float 数学重载、
`Bundle.module`、`@testable` 权限、Sendable、CF 桥接）和对应修法，可以先自查。

分界点很好判断：

- **错误在 `SpektraCore` 里** → 核心没编译过，问题集中；
- **错误只在测试里** → 核心已经过了，范围小得多，是好消息。

## 6. 之后（按这个顺序）

1. 修到 `swift test` 全绿；
2. 建工程、真机出图；
3. 用真实照片看效果，调 `Simulator` 的默认参数（曝光、滤色片中性值）；
4. 再谈 Metal：先只搬 `printExpose` + `scan` 两段（占 95% 时间），
   设计见 `docs/07-metal-plan.md`；
5. 最后才是 RAW 导入和全分辨率。

## 7. 如果要在 Mac 上新增胶片

需要 Python 参考环境（约 5 分钟）：

```bash
cd spektrafilm
uv venv --python 3.13 .venv
uv pip install --python .venv/bin/python numpy scipy colour-science numba \
    opt-einsum scikit-image matplotlib OpenImageIO rawpy exiv2 lensfunpy
```

然后把 `Reference/bake_packs.py` 的 `PAIRS` 里加一行，跑：

```bash
PYTHONPATH=spektrafilm/src .venv/bin/python Reference/bake_packs.py
```

它会烘焙新 pack、回放验证（误差应 < 1e-5），并把 profile 复制进
`Swift/Sources/SpektraCore/Resources/`。
