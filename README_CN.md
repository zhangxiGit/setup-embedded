# setup-embedded — 嵌入式固件开发调试技能

为 Claude Code 提供嵌入式固件开发的完整调试闭环能力：配置自动发现、交叉编译、烧录、日志采集与验证。

## 近期改动（2026-07）

**日志采集工具从 rcw-tool 迁移到 EmbedLink（MCP 协议）。** 这是一次架构性升级：

| 维度 | 旧（rcw-tool） | 新（EmbedLink） |
|------|---------------|----------------|
| 通信协议 | CLI 子命令 | MCP Tool（`http` 传输） |
| 传输层 | USB HID | UART（MQTT 已支持，USB HID 规划中） |
| 日志查看 | `tail -n N` / `tail -f` / `grep` | `query_logs` + Agent 自行过滤 |
| 连接管理 | `monitor &` 后台进程 | create → connect → query → disconnect 显式生命周期 |
| 配置格式 | `## Tool A 日志`（旧格式，含 rcw-tool路径） | `## 日志采集`（新格式，含串口参数） |
| 配置迁移 | — | 自动检测旧格式并提示迁移 |
| 数据持久化 | 文件写入 | 内存 10K 环形缓冲（后续版本加持久化） |
| 实时推送 | `tail -f` 阻塞读取 | 暂不支持，需 Agent 定时轮询 |

## 支持的工具链

### 编译工具
- **Keil MDK (ARMCC)** — `UV4.exe` 命令行编译，支持 `.uvprojx` 工程
- **GCC (arm-none-eabi-gcc)** — CMake 工程

### 调试探针 / 烧录
- **J-Link** — SWD 接口，自动生成 `flash.jlink` 脚本
- **ST-Link** — `st-flash` 命令行
- **OpenOCD** — 通用调试适配器

### 日志采集
- **EmbedLink** — 桌面应用（Tauri），通过 MCP Server（`127.0.0.1:3000`）提供日志采集能力
- 传输协议：UART（主）、MQTT（已支持）
- USB HID：计划在后续版本中支持

## 工作流程

### 1. 首次使用 — 配置向导

当项目根目录缺少 `.claude/embedded-config.md` 时自动触发。每步先自动扫描，检测不到才询问用户：

1. 扫描编译工具链（Keil UV4.exe、arm-none-eabi-gcc）
2. 扫描调试探针（JLink.exe、st-flash）
3. 扫描工程文件（`.uvprojx`、`CMakeLists.txt`）
4. 解析芯片型号（从工程文件提取）
5. 检测日志通道（搜索源码中的 UART 引脚定义和波特率）
6. 调用 `list_serial_ports` 列出可用串口供选择
7. 写入 `.claude/embedded-config.md`

生成的配置文件结构：

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

### 2. 旧配置自动迁移

如果检测到旧版 `.claude/embedded-config.md`（含 `rcw-tool路径` 或 `## Tool A 日志` 标题），自动提示迁移：

- 删除 `## Tool A 日志` 段
- UART 参数迁移到新的 `## 日志采集` 段
- USB HID 参数加注释保留，标注 "EmbedLink 后续版本支持"
- `## 编译` 和 `## 烧录` 段原样保留

### 3. 开发闭环

```
1. 改代码
2. 确认 EmbedLink 健康检查通过 → curl http://127.0.0.1:3000/health
3. 编译 → 确认 build.log 含 "0 Error(s)"
4. 找 HEX → ls -t <HEX目录>/*.hex | head -1
5. 烧录 → J-Link 确认 "O.K." 无 "Skipped"
6. create_uart_connection → 记录 connection_id → connect
7. send_serial_data 发控制指令（如需重置/开启日志）
8. query_logs (limit=50) → 查看启动日志
9. 分析 display_text 中的关键信息 → 验证改动
   没问题 → 报告用户验证结果
   有问题 → 分析日志 → 改代码 → 重建连接清旧数据 → 回到步骤3
```

### 4. EmbedLink 加载流程

每次调用 `/setup-embedded` 时执行：

1. **健康检查** — `curl -s http://127.0.0.1:3000/health`，预期返回 `ok`
2. **健康检查失败** → 提示用户启动 EmbedLink（`cargo tauri dev` 或桌面快捷方式）
3. **健康检查成功** → 验证 MCP 工具可用（调用 `list_connections`）
4. **MCP 未配置** → 提示在 `.mcp.json` 中添加 `{"embedlink": {"type": "http", "url": "http://127.0.0.1:3000/mcp"}}`

## EmbedLink MCP Tool 速查

### 核心工具

| MCP Tool | 用途 | 关键参数 |
|----------|------|---------|
| `list_serial_ports` | 列出可用 COM 口 | — |
| `create_uart_connection` | 创建 UART 连接 | `port_name`, `baud_rate`, `data_bits`, `stop_bits`, `parity`, `flow_control` |
| `connect` | 打开连接，开始接收数据 | `connection_id` |
| `disconnect` | 关闭连接（可复用） | `connection_id` |
| `delete_connection` | 删除连接（不可恢复） | `connection_id` |
| `update_connection` | 修改连接配置 | `connection_id` + 要改的字段 |
| `query_logs` | 查看日志 | `connection_id`（可选）, `limit`（默认 100，最大 10000） |
| `send_serial_data` | 向设备发送控制指令 | `connection_id`, `data`, `format`（`"hex"` 或 `"ascii"`） |
| `list_connections` | 查看所有连接状态 | — |

### MQTT 工具（已支持）

| MCP Tool | 用途 |
|----------|------|
| `create_mqtt_connection` | 创建 MQTT 连接 |
| `send_mqtt_message` | 发送 MQTT 消息 |
| `mqtt_subscribe` / `mqtt_unsubscribe` | 运行时动态订阅/取消 Topic |

### 应用设置

| MCP Tool | 用途 |
|----------|------|
| `get_settings` | 读取 EmbedLink 设置（主题、日志级别、MCP 端口等） |
| `save_settings` | 修改并保存 EmbedLink 设置 |

## rcw-tool → EmbedLink 命令映射

| rcw-tool 命令 | EmbedLink 等效操作 |
|---------------|-------------------|
| `monitor &` | `create_uart_connection` + `connect` |
| `log on` / `log off` | `send_serial_data`（控制指令取决于固件协议） |
| `tail -n N` | `query_logs`（`limit: N`） |
| `tail -f` | 定期调用 `query_logs` 轮询 |
| `grep "关键词"` | Agent 自行过滤 `query_logs` 返回的 `display_text` |
| `clear -f` | `disconnect` → `delete_connection` → 重建 + `connect` |
| `info` | `list_connections` + `query_logs` |
| `kill %1` | `disconnect` |

## EmbedLink 当前能力差距

| 功能 | 状态 | 变通方案 |
|------|------|---------|
| 文本搜索 | `query_logs` 无内容过滤 | Agent 自行过滤 JSON |
| 时间范围过滤 | 仅支持 `connection_id` + `limit` | Agent 按 `timestamp` 筛选 |
| 清空日志 | 无独立 `clear` 命令 | 重建连接隔离旧数据 |
| 实时推送 | 请求-响应模式 | Agent 定时轮询 |
| 数据持久化 | 内存 10K 环形缓冲 | 定期导出到文件 |
| USB HID 支持 | 仅 UART / MQTT | 等待后续版本 |
| 固件烧录 | MCP tool 为占位 | 继续用 J-Link/ST-Link/OpenOCD 命令行 |
| MCP 端口配置 | 硬编码 3000 | 暂无需改动 |

## 故障排查速查

### 编译
| 现象 | 处理 |
|------|------|
| 编译秒过但 HEX 没更新 | ARMCC5 不检测 `.h` 变更 → 删 `.axf`/`.bin`，`-r` rebuild |
| 版本号改了设备显示旧版本 | `fromelf --text -s <target>.axf \| grep <符号>` 验证 |

### 烧录
| 现象 | 处理 |
|------|------|
| J-Link `Skipped` | 改动未生效，检查编译产物是否真的更新了 |
| J-Link DAP 初始化失败 | 设备断电再上电后重试 |
| SWD 锁死 | BOOT0=1 上电 → 擦除 → BOOT0=0 |

### EmbedLink
| 现象 | 处理 |
|------|------|
| 健康检查 `Connection refused` | 启动 EmbedLink（`cargo tauri dev` 或桌面快捷方式） |
| `list_serial_ports` 返回空 | 检查 USB 线连接；确认驱动（CH340/CP210x）已安装 |
| `connect` 失败 | 关闭 Putty / 串口助手；检查设备是否上电 |
| `query_logs` 无数据 | 检查波特率配置；用 `send_serial_data` 发送控制指令 |
| `send_serial_data` 无响应 | 确认指令格式与固件协议一致；尝试 ASCII / hex 切换 |
| 返回大量历史数据 | 重建连接：`disconnect` → `delete_connection` → 重建 + `connect` |
| MCP Tool 返回 "Unknown tool" | 检查 `.mcp.json` 中的 embedlink HTTP 配置 |
| 烧录后无启动日志 | 等待 2-3 秒再查询；或 `send_serial_data` 主动触发 |

## 文件结构

```
setup-embedded/
├── SKILL.md                # Claude Code skill 定义（运行时加载）
├── embedlink-reference.md  # EmbedLink MCP Tool 详细参考
├── README.md               # 本文件
└── SKILL.md.bak            # 旧版备份（rcw-tool 版本，gitignore）
```

## 依赖

- **EmbedLink** 桌面应用（需在本地运行，监听 `127.0.0.1:3000`）
- Claude Code MCP 配置（`.mcp.json` 或全局 `mcp.json`）
- 编译工具链和调试探针（按项目需要安装）
