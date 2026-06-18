# setup-embedded — 嵌入式固件开发调试闭环

为 Claude Code 打造的嵌入式固件开发技能，覆盖**编译 → 烧录 → 日志采集**完整闭环。支持 Keil MDK (ARMCC)、GCC、J-Link、ST-Link、OpenOCD 等常用工具链，并集成 [rcw-tool](https://gitee.com/zhangxi95/zxx-log) 实时日志采集系统。

## 功能概览

| 阶段 | 能力 |
|------|------|
| **配置向导** | 自动扫描 Keil/ARMCC/GCC/J-Link/ST-Link 路径，解析芯片型号与工程文件 |
| **编译** | 调用 Keil UV4 或 GCC 编译，自动检查 "0 Error(s)"，增量编译问题自动处理 |
| **烧录** | 支持 J-Link / ST-Link / OpenOCD，自动生成烧录脚本并验证结果 |
| **日志采集** | 集成 rcw-tool，支持 USB HID / UART 实时日志，版本号验证，日志搜索与追踪 |

## 依赖工具

### 必须：rcw-tool

本 skill 的日志采集与设备诊断功能依赖 **rcw-tool**。

| 项目 | 地址 |
|------|------|
| 仓库 | [https://gitee.com/zhangxi95/zxx-log](https://gitee.com/zhangxi95/zxx-log) |
| 分支说明 | `master` — 使用文档；程序代码在其他分支 |

```bash
# 克隆 rcw-tool 文档（skill 会自动处理，也可手动执行）
git clone --depth 1 --branch master https://gitee.com/zhangxi95/zxx-log.git ~/.claude/rcw-tool-docs
```

> rcw-tool 可执行文件需要单独获取（非开源），请联系作者或在项目 release 页面下载。

### 可选：编译与烧录工具

- **Keil MDK** (UV4) — ARMCC 工具链
- **GCC** (`arm-none-eabi-gcc`) — 开源 ARM 工具链
- **J-Link** (Segger) — 调试探针
- **ST-Link** (`st-flash`) — STM32 调试探针
- **OpenOCD** — 开源调试工具

以上工具按需安装，skill 首次运行时会自动检测。

## 安装

### 方式一：通过 Claude Code 插件市场（推荐）

```bash
claude plugins install setup-embedded
```

### 方式二：手动安装

```bash
# 1. 克隆仓库
git clone https://github.com/zhangxiGit/setup-embedded.git

# 2. 复制到 Claude Code skills 目录
cp -r setup-embedded ~/.claude/skills/setup-embedded

# 3. 重启 Claude Code 或执行
claude /setup-embedded
```

### 方式三：直接复制 SKILL.md

如果你只需要核心定义文件：

```bash
mkdir -p ~/.claude/skills/setup-embedded
cp SKILL.md ~/.claude/skills/setup-embedded/
```

## 使用说明

### 首次使用：配置向导

在嵌入式项目根目录启动 Claude Code，执行：

```
/setup-embedded
```

首次运行会自动进入**配置向导**：

1. **扫描编译工具链** — 自动检测 C-F 盘中的 Keil UV4 和 `arm-none-eabi-gcc`
2. **扫描调试探针** — 自动检测 J-Link、ST-Link 路径
3. **扫描工程文件** — 查找 `.uvprojx` 或 `CMakeLists.txt`
4. **解析芯片型号** — 从工程文件中提取 MCU 型号
5. **日志通道检测** — 自动识别 UART 或 USB HID 日志参数

检测不到的项会询问用户，配置写入 `.claude/embedded-config.md`。

### 开发闭环

```
1. 改代码
2. 编译 → 确认 "0 Error(s)"
3. 找 HEX → 烧录文件
4. 烧录 → 确认 "O.K."
5. 启动日志采集 → rcw-tool monitor &
6. 重置日志 → rcw-tool log off && rcw-tool log on
7. 查看启动日志 → rcw-tool tail -n 50
8. 验证改动 → rcw-tool grep "关键词" -i
```

### rcw-tool 常用命令

```bash
rcw-tool monitor &                  # 启动日志采集（后台运行，Web UI 在 localhost:8080）
rcw-tool log off && rcw-tool log on # 重置日志状态，抓取完整启动日志
rcw-tool tail -n 50                 # 查看最近 50 行日志
rcw-tool tail -f                    # 实时追踪日志（Ctrl+C 退出）
rcw-tool grep "关键词" -i           # 搜索日志
rcw-tool grep "ERROR" -i -n 3       # 搜索错误并显示上下文
rcw-tool grep "关键词" -i --time 2m # 搜索最近 2 分钟内的匹配
rcw-tool clear -f                   # 清空旧日志（新一轮测试前）
rcw-tool info                       # 查看采集状态
pkill rcw-tool                      # 停止采集
```

## 支持的硬件平台

- STM32 全系列（L4 / F4 / WL / G0 / H7 等）
- nRF52 / nRF53 系列
- ESP32 系列
- RP2040（规划中）

## 配置文件示例

skill 生成的 `.claude/embedded-config.md`：

```markdown
# 嵌入式调试配置
## 编译
- 工具: Keil
- UV4路径: D:/Keil_v5/UV4/UV4.exe
- 工程文件: Keil/xxx.uvprojx
- HEX目录: Keil/
## 烧录
- 工具: JLink
- JLink路径: D:/Keil_v5/ARM/Segger/JLink.exe
- 芯片型号: STM32L452VC
- 接口: SWD
- 速度: 4000
## Tool A 日志
传输: USB_HID
VID: 0x04D8
PID: 0x0360
日志msgID: 0x800E
开日志: CONTROL_MSG
rcw-tool路径: C:/Tools/rcw-tool/rcw-tool.exe
```

## 许可证

MIT

## 作者

zhangxiGit — 与 Claude Code 协作开发
