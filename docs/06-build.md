# 编译与验证（Mac 侧清单）

## 1. 核心先跑通

一条命令做完 build → test → probe → bench，出错会指出停在哪一步：

```bash
bash Tools/mac-first-run.sh
```

或者手动：

```bash
cd "…/Swift"
swift test
```

预期：**约 30 个测试全绿**，且每条对拍测试会打印自己的误差，例如

```
stage1 max |diff| = 1.2e-06, mean = 3.1e-07, worst index 511
stage2 max |diff| = 1.5e-06, mean = 4.0e-07, worst index 733
...
end-to-end max |diff| = 2.2e-06, mean = 5.1e-07
```

判据：**max |diff| < 2e-5**。超过说明是公式/索引问题，不是精度问题
（Python 侧同算法实测 1e-7 量级）。

然后：

```bash
swift run spektra-probe
```

预期输出（数值可能因 profile 版本略有差异）：

```
film  Kodak Portra 400 [negative]
      81 wavelengths, 256 curve samples, reference illuminant D55
...
stage 1 (rgb -> log_e_film)    max |diff| = ...
stage 2 (log_e_film -> cmy_film) max |diff| = ...
stage 3 (cmy_film -> log_e_print) max |diff| = ...
stage 4 (log_e_print -> cmy_print) max |diff| = ...
stage 5 (cmy_print -> rgb_out)  max |diff| = ...
```

## 1b. 不用 Xcode，先出一张真图（推荐）

```bash
swift run spektra-cli ~/Pictures/photo.heic /tmp/out.png
swift run spektra-cli photo.heic out.png --pack kodak_ektar_100__kodak_portra_endura \
    --ev 0.3 --magenta 5 --print 1.05 --max-edge 2400
swift run spektra-cli --packs        # 列出内置胶片
```

它和 App 走**完全相同**的代码路径（解码 → 渲染 → 写 PNG），只是没有界面。
输出：

```
4032x3024  (12.2 MP)
  pack    kodak_portra_400__kodak_portra_endura   120 ms
  decode  310 ms
  render  2480 ms  (0.20 s/MP)
  write   420 ms
  -> out.png
```

`render` 那一行就是真机性能的 Mac 参照（M 系列比 iPhone 快一些，数量级一致）。
如果这里就要好几秒，说明 CPU 版对全尺寸偏慢，Metal 才值得做。

不需要照片也能量：

```bash
swift run spektra-cli --bench 2048
```

```
2048x2048  (4.19 MP)
  render  1020 ms  (0.24 s/MP)
  threads auto
```

## 2. 建 iOS 工程

见 [App/README.md](../App/README.md)。要点：

- Xcode 16 ▸ New ▸ iOS App ▸ SwiftUI
- 把 `App/Sources/*.swift` 拖进 target
- File ▸ Add Package Dependencies ▸ Add Local ▸ 选 `Swift/`
- 部署目标 iOS 17.0

## 3. 最常见的编译错误（按概率排序）

| 现象 | 原因 | 修法 |
|---|---|---|
| `no exact matches in call to global function 'exp'` | Float 数学重载没找到 | 代码里应该已经全部走 `expF/logF/log10F/powF`（见 `MathCompat.swift`）；如果还有漏网的，把调用改成对应的 `*F` 版本 |
| `value of type 'SIMD3<Float>' has no member …` | 用了 SIMD4 的写法 | 检查 `ChromaTable.lookup` 里 `wx[i] = …` 必须 `var wx` |
| `cannot find 'Bundle' in scope` / `Bundle.module` 报错 | target 没有声明资源 | `Package.swift` 里 `SpektraCore` 必须有 `resources: [.copy("Resources")]` |
| `'Golden' initializer is inaccessible due to 'private' protection level` | 成员初始化器被私有属性拖成 private | 只在 `Golden` 自己的 `static func load` 里调用，别在测试里 `Golden(entries:blob:)` |
| `main actor-isolated … can not be referenced from a non-isolated context` | Swift 6 严格并发 | 工程的 Swift Language Version 设成 **Swift 5**（Xcode 默认就是）；`ContentView.load()` 已标 `@MainActor` |
| `cannot convert value of type 'Data' to expected argument type 'CFMutableData'` | Core Foundation 桥接 | App 里已经改成 `CGImageDestinationCreateWithURL`，不再用 `NSMutableData` |
| 测试里 `XCTAssertEqual` 的 `accuracy` 类型不匹配 | Float vs Double | `accuracy:` 的字面量会被推断成 Float，不用显式写 |

## 4. 报错怎么发给我

贴**前 3 条**就够——后面的多半是第一条的连锁。如果错误在测试文件里，
说明核心已经编译过了，那是好消息，问题范围会小很多。

另外附上 `swift --version` 和 `xcodebuild -version`。

## 5. 提交前自查（Windows 上也能跑）

```bash
python Tools/check-syntax.py     # tree-sitter 解析，查语法错误
python Tools/check-sources.py    # UTF-8 / BOM / 括号配对
python Tools/check-resources.py  # Swift 引用的数组名是否存在于 pack
python Tools/verify.py           # 重出 golden 并跑五段数值对拍
python Tools/typecheck-remote.py --with-tests   # 真编译器类型检查（网络）
```

`typecheck-remote.py` 把 `SpektraCore` 的 14 个源文件和 9 个测试文件合成一个
文件，POST 到 godbolt.org 的 Swift 编译器做 `-typecheck`。已对 6.0.3 / 6.1 / 6.2
全部通过——**所以 `swift build` 大概率是干净的**，剩下的风险集中在
`ImageBridge.swift`（CoreGraphics）和 App 的 SwiftUI 代码。

`check-sources.py` 存在是因为在 Windows 上用 PowerShell 的 `Set-Content` 改过源码，
会把文件写成 GBK（已经发生过一次，两个文件被写成非 UTF-8，Swift 会直接读不了）。
