# EmbedLink MCP Tool 参考

EmbedLink 通过 MCP 协议（SSE 传输，`http://127.0.0.1:3000/mcp`）替代 rcw-tool 提供日志采集。

## rcw-tool → EmbedLink 命令映射

| rcw-tool | EmbedLink MCP Tool |
|----------|-------------------|
| `monitor &` | `create_uart_connection` + `connect` |
| `log on` / `log off` | `send_serial_data`（控制指令取决于固件协议） |
| `tail -n N` | `query_logs`（`limit: N`） |
| `tail -f` | 定期轮询 `query_logs` |
| `grep "关键词"` | Agent 自行过滤 `query_logs` 返回的 `display_text` |
| `clear -f` | `disconnect` → `delete_connection` → 重建 + `connect` |
| `info` | `list_connections` + `query_logs` |
| `kill %1` | `disconnect` |

## 核心 MCP Tool

### 串口管理
| Tool | 用途 |
|------|------|
| `list_serial_ports` | 列出可用 COM 口 |
| `create_uart_connection` | 创建 UART 连接（参数：`port_name`, `baud_rate`, `data_bits`=8, `stop_bits`="one", `parity`="none", `flow_control`="none"） |
| `connect` | 打开连接，开始接收数据 |
| `disconnect` | 关闭连接（可复用） |
| `delete_connection` | 删除连接 |
| `update_connection` | 修改连接配置，无需重建 |

### 日志操作
| Tool | 用途 |
|------|------|
| `query_logs` | 查询日志（`connection_id` 可选，`limit` 默认 100，最大 10000） |
| `send_serial_data` | 向设备发送控制指令（`data`, `format`: `"hex"` 或 `"ascii"`） |
| `list_connections` | 查看所有连接状态 |

### query_logs 返回格式

每条记录包含 `direction`（`"rx"`=设备输出 / `"tx"`=发送）、`display_text`、`timestamp`（毫秒）、`source`。

### MQTT 工具
| Tool | 用途 |
|------|------|
| `create_mqtt_connection` | 创建 MQTT 连接 |
| `send_mqtt_message` | 发送 MQTT 消息 |
| `mqtt_subscribe` / `mqtt_unsubscribe` | 动态订阅/取消 Topic |

### 应用设置
| Tool | 用途 |
|------|------|
| `get_settings` / `save_settings` | 读取/修改 EmbedLink 设置（主题、日志级别、MCP 端口等） |

## 连接生命周期

```
create_uart_connection → connect → query_logs / send_serial_data → disconnect
                                                                      ↓
                                                          delete_connection（彻底删除）
```

- **清空旧日志：** `disconnect` → `delete_connection` → 重建 + `connect`
- **暂停采集：** `disconnect`（保留连接配置，下次 `connect` 复用）
- **修改参数：** `update_connection`（无需重建）

## 能力差距

| 功能 | 状态 | 变通方案 |
|------|------|---------|
| 文本搜索 | 无服务端过滤 | Agent 自行过滤 `display_text` |
| 时间范围过滤 | 仅 `connection_id` + `limit` | Agent 按 `timestamp` 筛选 |
| 清空日志 | 无 `clear` 命令 | 重建连接 |
| 实时推送 | 请求-响应模式 | Agent 定时轮询 |
| 数据持久化 | 内存 10K 环形缓冲 | 定期导出 |
| USB HID | 仅 UART / MQTT | 后续版本 |
| 固件烧录 | MCP tool 占位 | 继续用 J-Link/ST-Link/OpenOCD |
| MCP 端口 | 硬编码 3000 | 暂无需改动 |

> EmbedLink 支持 **UART** 和 **MQTT** 协议。USB HID 将在后续版本支持。
