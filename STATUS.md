# 状态快照

> 生成于第 38 轮。**没在这台机器上跑过 Swift**——所有 Swift 结论都来自
> Compiler Explorer 上的真编译器（`Tools/typecheck-remote.py`、
> `Tools/run-remote-tests.py`）。

## 结论

把 spektrafilm 的物理管线用 Swift 重写完毕，五段数值与 Python 参考一致到
1e-6 量级；iOS App（选图 / 三款胶片 / 四个控件 / 预览 / 全尺寸导出 / 自检）
代码写完但**尚未在真机上编译运行**。

## 证据

| 检查 | 命令 | 结果 |
|---|---|---|
| Swift 语法 | `python Tools/check-syntax.py` | 34 文件，0 错 |
| 编码/括号 | `python Tools/check-sources.py` | 34 文件，0 问题 |
| 资源完整性 | `python Tools/check-resources.py` | 4 manifest / 46 数组 / 3 pack / 4 profile，无缺失 |
| 文档引用 | `python Tools/check-docs.py` | 18 文档 / 29 引用，0 缺失 |
| Python 五段对拍 | `python Tools/verify.py` | 6e-8 ~ 3e-7，0 failing |
| Swift 类型 | `python Tools/typecheck-remote.py --with-tests` | 0 error（Swift 6.0.3 / 6.1 / 6.2） |
| Swift 数值 | `python Tools/run-remote-tests.py` | 见下 |

远程执行（每次浮动 2–3 倍，量级稳定）：

```
stage1 ~5e-07   stage2 ~4e-07   stage3 ~4e-07
stage4 ~7e-07   stage5 ~2e-06   simulator ~2e-06
filter ~1e-07   srgb   ~2e-07
threads-print 0.0    threads-scan 0.0    strips 0.0
```

最后三行是**逐位相同**：并行 vs 串行、条带 vs 整帧。

## 已验证 / 未验证

| 已验证 | 未验证 |
|---|---|
| 五段物理管线（数值） | `ImageBridge`（CoreGraphics，~110 行） |
| `Simulator` 端到端 | `SpektraCLI`（~170 行） |
| 放大机二向色模型 | `App/`（SwiftUI，~380 行） |
| sRGB 传递函数 | 真机性能 |
| 并行与条带一致性 | Metal |
| 资源与 pack 完整性 | |
| Python 参考与 golden 的确定性 | |

## 体积

| 项 | 值 |
|---|---|
| Swift 源码（核心 + probe + CLI） | 20 文件 / 1,989 行 |
| Swift 测试 | 10 文件 / 708 行 |
| App 源码 | 5 文件 / 805 行（布局参考 SpektraLab，见 `App/README.md`） |
| 烘焙数据 | golden 0.53 MB + 3 pack 1.34 MB + 4 profile 0.86 MB |
| 交付包 | 95 文件 / 2.37 MB |

## 在 Mac 上

```bash
bash Tools/mac-first-run.sh              # build → test → probe → bench
swift run spektra-cli --bench 1024       # 有多快
swift run spektra-cli photo.heic out.png # 第一张真图
```

出错时贴 `STOPPED AT:` 之后的内容。

## 还剩什么

| 项 | 前置条件 | 参考 |
|---|---|---|
| 真机首跑 | 一条 Mac 命令 | `docs/06-build.md` |
| Metal | 真机 benchmark 数字 | `docs/12-metal-draft.md` |
| 颗粒 / 光晕 | 需要重做条带（halo），会破两条不变量 | `docs/09-limitations.md` §4 |
| CAM16 输出压缩 | 无 | `docs/09-limitations.md` §5 |
| RAW | 无（`CIRAWFilter`） | `docs/09-limitations.md` §6 |
| 更多胶片 | 一行数据 + 重烘 | `Reference/bake_packs.py` |

接手说明见 `docs/13-resume.md`。
