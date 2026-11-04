# Reference：Python 参考实现与 golden

`spektrafilm/` 是上游仓库（克隆进来，commit `3bb2c2d`），`spektrafilm/.venv` 是它的
Python 3.13 环境。golden 数据由它产生，Swift 侧只做消费者。

## 环境（已在本机建好）

```powershell
cd spektrafilm
$env:UV_CACHE_DIR="..\.uv-cache"; $env:UV_PYTHON_INSTALL_DIR="..\.uv-python"
uv venv --python 3.13 .venv
uv pip install --python .venv\Scripts\python.exe numpy scipy colour-science numba `
    opt-einsum scikit-image matplotlib OpenImageIO rawpy exiv2 lensfunpy
```

注意：所有 `uv` 的缓存/解释器目录必须指到工作区内，否则沙箱写不进去。

## 脚本

| 文件 | 作用 |
|---|---|
| `export_goldens.py` | 跑一遍参考管线，导出各 tap 与烘焙常量 |
| `check_stage1.py` | 校验 `rgb → log_e_film`（也是后续脚本的公共工具） |
| `check_stage2.py` | 校验 `log_e_film → cmy_film` |
| `check_stage3.py` | 校验 `cmy_film → log_e_print` |
| `check_stage4.py` | 校验 `log_e_print → cmy_print` |
| `check_stage5.py` | 校验 `cmy_print → rgb_out` |

统一起见，用 `python Tools/verify.py` 一次跑完。

## golden 容器

`goldens/manifest.json` + `goldens/arrays.bin`：所有数组打包成一个小端 float32 块，
manifest 记录名称、形状、偏移（**偏移以 float 为单位**）。Swift 的 `Golden` 读同一格式。

## 改参数时注意

`export_goldens.py` 固定用 `debug.lut_mode = True`（关掉颗粒/光晕/自动曝光，
成色剂保留），并把输出色域压缩设为 `"off"`——CAM16 压缩还没移植。
如果改了这里的配置，Swift 侧的期望值要跟着变。
