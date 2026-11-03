# 安显 V57 r7 源码交付包

整理日期：2026-11-03。对应当前已固化到 Flash 并通过断电自启动确认的 V57 r7。
不包含倒计时工程、失败的 V57 r2 固件、其他历史工程和开发工具安装包。

## 从这里开始

1. 阅读 `docs/操作说明.md`，查看演示与按键操作。
2. 阅读 `docs/代码导航.md`，查看主要模块位置。
3. 运行 `python tools/verify_package.py`，核对交付文件。
4. 需要重新构建时，运行 `python tools/prepare_build.py --out output/build`。
5. 用已安装的 TD 命令行程序执行生成的 `output/build/build.tcl`。

```powershell
python tools/verify_package.py
python tools/prepare_build.py --out output/build
& 'C:/Anlogic/TD/bin/td_commands_prompt.exe' "$PWD/output/build/build.tcl"
```

将最后一行的 TD 安装位置替换为实际位置。输出目录必须不存在，重复构建请指定新目录。

## 目录

| 路径 | 内容 |
|---|---|
| `project_v57/rtl` | 应用 RTL、字体/字幕 ROM 和初始化数据 |
| `project_v57/source` | 顶层、厂商 HDMI/SDRAM IP、引脚与时序约束 |
| `project_v57/td_project` | PLL、复位边界约束、原始部署配置 |
| `tools` | 完整性校验和可迁移构建准备脚本 |
| `firmware` | 已通过 Flash 读回校验的 V57 r7 bit |
| `records/build` | 冻结配方、源码散列、时序/资源报告 |
| `records/flash` | Flash 写入、备份散列、读回校验与冷启动记录 |
| `records/validation` | 21 项原有自动验证报告 |
| `records/media` | 原 TF 配套素材和写入记录 |
| `docs` | 操作说明和模块导航 |

## 版本与交付边界

- 器件：EG4S20BG256；工具：TD 6.2.168.116；候选：r7。
- 固件 SHA-256：`FDC16B876B07ED18F6017BB9A607C440CEA837E7415D72363478C739F9A0AA0D`。
- 原构建最终时序：setup WNS +0.199 ns，hold WNS +0.019 ns，布线 DRC 通过。
- 2026-11-03 22:46 完成 Flash 写入和工具原生读回校验，22:48 记录断电自启动及功能抽查确认。
- HDMI 输出为 1280×720，视频素材为 640×360、基准 15 fps；两者不是同一分辨率指标。
- EQ 七档为 -24、-18、-12、-6、0、+3、+6 dB 的设计标称值，未进行绝对增益实测。
- 源码原件逐字节保留，与冻结构建核对了 141 个文件。`prepare_build.py` 只在独立输出副本中替换路径，不修改本包源码。
- 原源码含本机绝对路径，应通过准备脚本生成本地构建目录。准备脚本不连接开发板，也不写 Flash/TF。
- 文件名中的 v37/v38/v39/v48 等是 V57 实际依赖的模块名，保留这些文件是为了保持完整构建。
- 本次整理验证文件散列、压缩包内容和构建依赖，不重新综合、布局布线或执行整套 RTL 仿真；已有验证结果保留在 `records`。
- TF 的大体积播放素材、2 MiB 旧 Flash 备份原始二进制和工具安装程序不在本包中；实板播放需使用原有配套 TF 卡。原始记录中的旧路径仅供追溯。
