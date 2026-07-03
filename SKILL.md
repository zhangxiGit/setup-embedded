 ---
name: setup-embedded
description: Use when developing, debugging, building, or flashing embedded firmware projects. Invoke with `/setup-embedded` — auto-detects if first-time setup is needed. Triggers on requests to compile, build, flash, or test firmware changes on hardware. Supports Keil MDK (ARMCC), GCC, J-Link, ST-Link, OpenOCD. Uses EmbedLink desktop app for log collection via MCP.
---

# 嵌入式固件开发调试闭环

## 加载后

检查项目根目录的 `CLAUDE.md`（有则参考）和 `.claude/embedded-config.md`：

- **两者都不存在** → 配置向导：自动扫描工具链/调试器/工程文件 → 写入 `.claude/embedded-config.md`
- **配置存在** → 读取配置，等待开发任务

### EmbedLink 准备

EmbedLink 是本项目的桌面调试工具，通过 MCP Server 提供日志采集能力，替代 rcw-tool。

**1. 健康检查：**

```bash
curl -s http://127.0.0.1:3000/health
```

预期输出：纯文本 `ok`。

**2. 健康检查失败时（连接拒绝 / 超时 / 非 "ok"）：**

提示用户：
> EmbedLink 未启动。请先启动 EmbedLink 桌面应用，然后重新运行 `/setup-embedded`。
> 启动方式：在 `embedlink/` 目录下执行 `cargo tauri dev`，或双击已安装的 EmbedLink 快捷方式。
> EmbedLink 启动后会自动在 `127.0.0.1:3000` 启动 MCP Server。

**3. 健康检查成功时：**

尝试验证 MCP 工具可用（调用 `list_connections`）。如果返回 "Unknown tool" 错误：
> MCP 工具不可用。请确认 Claude Code 配置中包含 EmbedLink 的 MCP Server：
> ```json
> {"embedlink": {"type": "sse", "url": "http://127.0.0.1:3000/mcp"}}
> ```
> 项目级配置放在 `.mcp.json`，全局配置放在 `mcp.json` 的 `mcpServers` 中。

**4. 读取 `.claude/embedded-config.md`：**

- 如果包含旧格式（含 `rcw-tool路径` 或 `## Tool A 日志` 标题）：
  - 提示用户："检测到旧版 rcw-tool 配置。EmbedLink 已替换 rcw-tool，是否自动迁移？"
  - 用户同意后：删除 `## Tool A 日志` 段；UART 参数（如 COM 口、波特率）迁移到新 `## 日志采集` 段；USB HID 参数（VID/PID）加注释保留，标注 "EmbedLink 后续版本支持"
  - `## 编译` 和 `## 烧录` 段原样保留
- 如果是新格式，直接使用

---

## EmbedLink 日志采集概述

EmbedLink 替代 rcw-tool，通过 MCP 协议提供日志采集。核心 MCP Tool 映射：

| rcw-tool 命令 | EmbedLink MCP Tool | 说明 |
|---------------|-------------------|------|
| （无，自动检测） | `list_serial_ports` | 列出可用 COM 口 |
| `monitor &` | `create_uart_connection` + `connect` | 创建 UART 连接并打开（开始接收数据） |
| `log on` / `log off` | `send_serial_data` | 向设备发送控制指令 |
| `tail -n N` | `query_logs` (connection_id 可选, limit 默认 100) | 查看最近 N 条日志 |
| `tail -f` | 定期调用 `query_logs` 轮询 | 当前无实时推送，需手动轮询 |
| `grep` 关键词 | 无服务端搜索，Agent 自行过滤 | 从 query_logs 返回 JSON 中匹配 display_text |
| `clear -f` | disconnect → delete_connection → 重建 + connect | 通过重建连接隔离旧数据 |
| `info` | list_connections + query_logs | 查看连接状态和日志统计 |
| `kill %1` | disconnect | 关闭连接 |
| — | `update_connection` | 修改连接配置（如波特率），无需重建连接 |
| — | `create_mqtt_connection` + `connect` | 创建 MQTT 连接并打开 |
| — | `send_mqtt_message` | 发送 MQTT 消息 |
| — | `mqtt_subscribe` / `mqtt_unsubscribe` | 运行时动态订阅/取消 MQTT Topic |
| — | `get_settings` / `save_settings` | 读取/修改 EmbedLink 应用设置（主题、日志级别、MCP 端口等） |

> EmbedLink 支持 **UART** 和 **MQTT** 协议。USB HID 将在后续版本支持。本 skill 聚焦 UART 日志采集，MQTT 工具详见 EmbedLink 文档。

---

## 配置向导

`.claude/embedded-config.md` 不存在时执行。每步先自动检测，检测不到才问用户。

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

1. 检查 CLAUDE.md 或源码（`general.h`、`main.c`）中的 UART 引脚定义：
   - 搜索 `TX`/`RX`/`USART` 引脚宏定义和初始化代码
   - 提取波特率（常见：115200、921600、1000000）
2. 如果源码中找不到 UART 配置：
   - 询问用户设备使用的串口号和波特率
   - 如果用户不确定，调用 `list_serial_ports` 列出当前可用串口供选择
3. USB HID：当前暂不支持。如果用户使用 USB HID 日志设备，告知 EmbedLink 后续版本会添加。

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

日志 `build.log` 在项目根目录，确认含 "0 Error(s)"。

> ARMCC5 增量编译不检测 `.h` 变更。如果改了 `.h` 文件后编译秒过但产物未更新：删 `.axf`/`.bin` 后用 `-r` rebuild。

### 找烧录文件

```bash
ls -t <输出目录>/*.hex 2>/dev/null | head -1
```

### 烧录

J-Link:
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

ST-Link: `st-flash --reset write <bin文件> 0x08000000`
OpenOCD: `openocd -f interface/stlink.cfg -f target/<芯片>.cfg -c "program <hex> verify reset exit"`

### 日志采集（EmbedLink）

#### 建立 UART 连接

每次闭环开始时，确保 UART 连接已建立：

1. 如果尚无可用的 UART 连接，先创建：
   - 调用 `list_serial_ports` 确认目标串口存在
   - 调用 `create_uart_connection`，参数来自 `.claude/embedded-config.md` 的 `## 日志采集` 段：
     ```
     port_name: <串口号>
     baud_rate: <波特率>
     data_bits: <数据位，默认 8>
     stop_bits: <停止位，默认 "one">
     parity: <校验，默认 "none">
     flow_control: <流控，默认 "none">
     ```
   - **记录返回的 `connection_id`**，后续所有操作都需要用到

2. 打开连接：
   - 调用 `connect`，参数 `connection_id: <上一步的 ID>`
   - 确认返回的 status 为 "connected"

3. 连接失败时：
   - 检查设备 USB 转串口线是否已插入
   - 检查串口号是否被其他程序占用（Putty、串口助手等）
   - 重新调用 `list_serial_ports` 确认端口仍在

#### 查看日志

调用 `query_logs`：
```
connection_id: <UART 连接 ID>（可选，省略时查询所有连接）
limit: 50
```

返回 JSON 数组，每条记录包含：
- `direction`: `"rx"`（设备输出）或 `"tx"`（发出的数据）
- `display_text`: 格式化后的文本内容
- `timestamp`: 毫秒时间戳
- `source`: `"agent"` / `"user"` / `"system"`

如果数据量大，增大 `limit`（最大 10000）。

#### 搜索日志

EmbedLink 当前不支持服务端文本搜索。Agent 自行过滤：

1. 调用 `query_logs`，`limit` 设大一些（如 200~500）
2. 在返回数组中检查 `display_text` 字段，匹配关键词
3. 如需更多上下文，多次调用覆盖不同范围

#### 控制日志开关

调用 `send_serial_data` 发送控制指令：

```
connection_id: <UART 连接 ID>
data: <控制指令内容>
format: "hex" (十六进制) 或 "ascii" (文本)
```

具体控制指令取决于固件协议。如果不确定格式，用 `"ascii"` 格式尝试。

#### 新一轮测试前清空旧日志

EmbedLink 无独立 `clear` 命令，通过重建连接实现：

1. 调用 `disconnect`，`connection_id: <ID>`
2. 调用 `delete_connection`，`connection_id: <ID>`
3. 重新 `create_uart_connection` + `connect`（新 ID，旧数据不会出现在按新 ID 查询的结果中）

#### 停止采集

调用 `disconnect`，`connection_id: <ID>`（不删除连接，下次可直接 `connect` 复用）。

### 完整闭环流程

```
1. 改代码
2. 确认 EmbedLink 健康检查通过
3. 编译 → 确认 "0 Error(s)"
4. 找 HEX → ls -t <HEX目录>/*.hex | head -1
5. 烧录 → J-Link 确认 "O.K." 无 "Skipped"
6. create_uart_connection → 记录 connection_id → connect
7. send_serial_data 发控制指令（如需重置/开启日志）
8. query_logs (limit=50) → 查看启动日志
9. 分析 display_text 中的关键信息 → 验证改动
   没问题 → 报告用户验证结果
   有问题 → 分析日志 → 改代码 → 重建连接清旧数据 → 回到步骤3
```

---

## EmbedLink 能力差距（待后续讨论）

以下功能在当前 EmbedLink 中不支持，计划在后续版本添加：

| 功能 | 当前状态 | 变通方案 |
|------|---------|---------|
| **文本搜索**（grep 等价） | `query_logs` 无内容过滤 | Agent 自行过滤返回的 JSON |
| **时间范围过滤** | `query_logs` 仅支持 connection_id + limit | Agent 自行按 timestamp 筛选 |
| **清空日志**（clear 等价） | 无独立 clear 命令 | 重建连接隔离旧数据 |
| **实时推送**（tail -f 等价） | MCP 为请求-响应模式，无持续推送 | Agent 定时轮询 query_logs |
| **数据持久化** | 内存 10K 环形缓冲，关闭后丢失 | 定期导出到文件 |
| **USB HID 支持** | 仅支持 UART / MQTT | 等待下一版本适配器实现 |
| **固件烧录**（flash_firmware） | MCP tool 为占位，未实现 | 继续使用 J-Link/ST-Link/OpenOCD 命令行 |
| **MCP 端口配置** | 硬编码 3000，不读取 settings | 暂无需改动，后续改为读取配置 |

---

## 故障排查

| 现象 | 原因 | 处理 |
|------|------|------|
| 编译秒过但 HEX 没更新 | ARMCC5 增量编译不检测 `.h` 变更 | 删 .o/.axf/.bin，`-r` rebuild；验证 HEX 时间戳 > 源文件 |
| J-Link 输出 `Skipped. Contents already match` | HEX 与 Flash 一致，未执行编程 | 说明改动未生效，回退检查编译产物是否真的更新了 |
| 版本号改了但设备显示旧版本 | 编译产物实际未含新值 | `fromelf --text -s <target>.axf \| grep <符号>` 查符号地址，grep HEX 验证字节 |
| HEX 文件名含旧版本号 | post-build 脚本用 .bin 中的版本号命名 | 文件名仅供参考，以内容为准；或直接用编译中间产物 |
| J-Link DAP 初始化失败 | 连接状态异常 | 设备断电再上电后重试 |
| SWD 锁死 | 用户程序禁用 SWD 引脚 | BOOT0=1 上电 → 擦除 → BOOT0=0 |
| EmbedLink 健康检查失败（Connection refused） | EmbedLink 未启动 | 执行 `cargo tauri dev` 或启动 EmbedLink 快捷方式 |
| `list_serial_ports` 返回空数组 | 设备未连接/驱动问题 | 检查 USB 转串口线连接；设备管理器确认 COM 口出现；安装 CH340/CP210x 驱动 |
| `create_uart_connection` 成功但 `connect` 失败 | 串口被占用/设备未就绪 | 关闭 Putty、串口助手等；检查设备是否上电 |
| `connect` 成功但 `query_logs` 无数据 | 设备日志未输出/波特率不匹配 | 检查波特率配置；用 send_serial_data 发送控制指令 |
| `send_serial_data` 发送控制指令后设备无响应 | 消息格式/协议不匹配 | 确认指令 hex 内容与固件协议一致；尝试 ASCII 格式 |
| `query_logs` 返回大量无关历史数据 | 缓冲区包含旧连接的数据 | 重建连接：disconnect → delete_connection → create_uart_connection → connect |
| EmbedLink MCP Tool 返回 "Unknown tool" | MCP 客户端未配置 | 检查 `.mcp.json` 或 `mcp.json` 中是否有 embedlink SSE 配置 |
| 烧录后 `query_logs` 无启动日志 | 设备刚上电，日志尚未输出 | 等待 2-3 秒再查询；或 send_serial_data 主动触发 |
