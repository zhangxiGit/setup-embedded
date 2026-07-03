---
name: setup-embedded
description: Use when developing, debugging, building, or flashing embedded firmware projects on bare-metal MCU (STM32, nRF, ESP32, RP2040) or RTOS (FreeRTOS, Zephyr, ThreadX) targets. Triggers on requests to compile, build, flash, or test firmware changes on hardware with Keil MDK, GCC, J-Link, or ST-Link.
---

# 嵌入式固件开发调试闭环

## Overview

编译 → 烧录 → 日志采集 的完整调试闭环。自动检测工具链和调试器，通过 EmbedLink（MCP 桌面应用）采集设备日志。

## When to Use

- 需要编译、烧录、验证嵌入式固件改动
- 项目使用 Keil MDK / GCC + J-Link / ST-Link / OpenOCD
- 需要通过串口日志验证设备行为

**When NOT to use:**
- 纯软件项目（无硬件目标）
- 使用其他调试工具链（如 IAR、Lauterbach）— 需扩展后才适用

## 加载后

检查项目根目录的 `CLAUDE.md`（有则参考）和 `.claude/embedded-config.md`：

- **两者都不存在** → [配置向导](#配置向导)
- **配置存在** → 读取配置，等待开发任务

### EmbedLink 准备

1. **健康检查：** `curl -s http://127.0.0.1:3000/health` → 预期 `ok`
2. **失败时** → 提示用户启动 EmbedLink（`cargo tauri dev` 或桌面快捷方式）
3. **成功时** → 调用 `list_connections` 验证 MCP 工具可用；若返回 "Unknown tool"，提示配置 `.mcp.json`：
   ```json
   {"embedlink": {"type": "sse", "url": "http://127.0.0.1:3000/mcp"}}
   ```
4. **读取 `.claude/embedded-config.md`：** 若含旧格式（`rcw-tool路径` 或 `## Tool A 日志`），提示迁移：删除 `## Tool A 日志`，UART 参数迁入 `## 日志采集`，USB HID 参数加注释保留。`## 编译` / `## 烧录` 原样保留。

> EmbedLink MCP Tool 详细参数和 rcw-tool 命令映射见 [embedlink-reference.md](embedlink-reference.md)。

---

## Quick Reference

| 操作 | 命令 / MCP Tool |
|------|----------------|
| 编译 | `UV4.exe -b <工程> -j0 -o build.log` |
| 找 HEX | `ls -t <HEX目录>/*.hex \| head -1` |
| 烧录 (J-Link) | 生成 `flash.jlink` → `JLink.exe -NoGui 1 -CommandFile flash.jlink` |
| 创建串口连接 | `create_uart_connection` + `connect` |
| 查看日志 | `query_logs`（`limit: 50`） |
| 清日志 | `disconnect` → `delete_connection` → 重建 + `connect` |

---

## 配置向导

`.claude/embedded-config.md` 不存在时执行。每步先自动扫描，检测不到才问用户。

### 扫描编译工具链

```bash
for d in C D E F; do
  find "/$d" -maxdepth 4 -path "*/Keil*/UV4/UV4.exe" 2>/dev/null | head -1
done
which arm-none-eabi-gcc 2>/dev/null
```

### 扫描调试探针

```bash
for d in C D E F; do
  find "/$d" -maxdepth 5 -path "*/Segger/JLink.exe" 2>/dev/null | head -1
done
which st-flash 2>/dev/null
```

### 扫描工程文件

```bash
find . -maxdepth 3 -name "*.uvprojx" -o -name "CMakeLists.txt"
```

### 解析芯片型号

从 `.uvprojx` 的 `<Device>` 标签或 CMakeLists 的 `CMSIS COMPONENTS` 提取。

### 烧录接口

默认 SWD，速度 4000。

### 日志通道检测

1. 搜索源码（`general.h`、`main.c`）中的 `TX`/`RX`/`USART` 引脚定义，提取波特率
2. 源码中找不到 → 询问用户串口号和波特率，或调用 `list_serial_ports` 供选择
3. USB HID：当前暂不支持，告知用户 EmbedLink 后续版本会添加

### 写入配置

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
## 日志采集
- 工具: EmbedLink
- 传输: UART
- 串口号: COM3
- 波特率: 115200
- 数据位: 8
- 停止位: 1
- 校验: 无
- 流控: 无
## EmbedLink
- 状态检查: http://127.0.0.1:3000/health
- MCP端点: http://127.0.0.1:3000/mcp
```

---

## 开发闭环

### 编译

```bash
cd <项目根目录> && cmd //c "<UV4路径> -b <工程文件绝对路径> -j0 -o <项目根目录绝对路径>\build.log" 2>&1
```

确认 `build.log` 含 "0 Error(s)"。

> ARMCC5 增量编译不检测 `.h` 变更。改 `.h` 后编译秒过但产物未更新 → 删 `.axf`/`.bin`，`-r` rebuild。

### 找烧录文件

```bash
ls -t <输出目录>/*.hex 2>/dev/null | head -1
```

### 烧录

**J-Link:**
```bash
cat > flash.jlink << JLINKEOF
device <芯片型号>
si <接口>
speed <速度>
loadfile <HEX绝对路径>
r
g
q
JLINKEOF
<JLink路径> -NoGui 1 -ExitOnError 1 -CommandFile flash.jlink
rm flash.jlink
```

**ST-Link:** `st-flash --reset write <bin文件> 0x08000000`
**OpenOCD:** `openocd -f interface/stlink.cfg -f target/<芯片>.cfg -c "program <hex> verify reset exit"`

### 日志采集（EmbedLink）

详见 [embedlink-reference.md](embedlink-reference.md)。核心操作：

**建立连接：** `list_serial_ports` → `create_uart_connection`（参数来自配置的 `## 日志采集`）→ `connect` → **记录 `connection_id`**

**查看日志：** `query_logs`（`connection_id`, `limit: 50`）。数据量大时增大 `limit`（最大 10000）。

**搜索日志：** `query_logs` 设 `limit: 200~500`，在返回的 `display_text` 中匹配关键词。

**控制日志：** `send_serial_data`（`format: "hex"` 或 `"ascii"`）。具体指令取决于固件协议。

**清旧日志：** `disconnect` → `delete_connection` → 重建 + `connect`。

**停止采集：** `disconnect`（不删除，下次可直接 `connect` 复用）。

### 完整闭环流程

```
1. 改代码
2. 确认 EmbedLink 健康检查通过
3. 编译 → 确认 "0 Error(s)"
4. 找 HEX → ls -t <HEX目录>/*.hex | head -1
5. 烧录 → 确认 "O.K." 无 "Skipped"
6. create_uart_connection → 记录 connection_id → connect
7. send_serial_data 发控制指令（如需重置/开启日志）
8. query_logs (limit=50) → 查看启动日志
9. 分析 display_text → 验证改动
   没问题 → 报告验证结果
   有问题 → 分析日志 → 改代码 → 重建连接清旧数据 → 回到步骤3
```

---

## Common Mistakes

| 错误 | 后果 | 正确做法 |
|------|------|---------|
| 改 `.h` 后用 `-b`（增量编译） | HEX 未更新，烧录后行为不变 | 删 `.axf`/`.bin`，`-r` rebuild |
| 烧录后不查 J-Link 输出 | 忽略 `Skipped` 导致以为已更新 | 确认无 `Skipped` 且含 `O.K.` |
| 用旧 connection_id 查日志 | 返回历史数据，误判为新日志 | 重建连接隔离旧数据 |
| 不验证 EmbedLink 健康检查直接操作 | `query_logs` 返回空 / "Unknown tool" | 先 `curl health` 再 `list_connections` |
| `send_serial_data` 格式不对 | 设备无响应 | 不确定时用 `"ascii"`，确认协议后换 `"hex"` |

---

## 故障排查

| 现象 | 处理 |
|------|------|
| 编译秒过但 HEX 没更新 | 删 `.axf`/`.bin`，`-r` rebuild |
| J-Link `Skipped` | 检查编译产物时间戳是否真的更新了 |
| J-Link DAP 初始化失败 | 设备断电再上电后重试 |
| SWD 锁死 | BOOT0=1 上电 → 擦除 → BOOT0=0 |
| EmbedLink `Connection refused` | 启动 EmbedLink |
| `list_serial_ports` 返回空 | 检查 USB 线 + CH340/CP210x 驱动 |
| `connect` 失败 | 关闭 Putty / 串口助手；检查设备上电 |
| `query_logs` 无数据 | 检查波特率；用 `send_serial_data` 触发 |
| MCP Tool 返回 "Unknown tool" | 检查 `.mcp.json` 中的 embedlink SSE 配置 |
| `query_logs` 返回大量历史数据 | 重建连接 |
