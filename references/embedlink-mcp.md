# EmbedLink MCP UART 操作规范

## 适用范围

debug、hardware test 与 full loop 的 UART port list、connect、disconnect、send、log query 只能通过 EmbedLink MCP Tool 完成。build 与 J-Link flash 不需要 EmbedLink MCP，也不得隐式启动 UART 操作。

## Runtime tool contract

当前 runtime 暴露的 EmbedLink MCP tool name、description 与 input schema 是唯一依据。先检查实际工具列表，再按原样使用 tool name 与 schema；不要猜测、硬编码或把本文中的 logical operation 当作真实 tool name。

logical operations：

| Operation | 目的 |
|---|---|
| Capability preflight | 用一个无副作用调用确认所需 EmbedLink MCP 能力存在且可调用 |
| List UART ports | 获取可用 UART port |
| Connect UART | 按统一配置建立连接并保存 runtime `connection_id` |
| Send UART | 通过现有连接发送测试数据 |
| Query logs | 获取带时间范围或游标的 UART log evidence |
| Disconnect UART | 关闭本次 runtime connection |

在首次 UART 操作前只执行一次 capability preflight。若用户仅请求 build 或 flash，不执行 preflight。

## MCP-only 边界

EmbedLink MCP Tool 缺失、schema 不匹配、返回错误或超时后，立即停止 UART debugging 并报告。不得：

- 自动 retry 同一 MCP 调用；
- 启动、重启或修复 EmbedLink；
- 调用 HTTP endpoint 或其他非 MCP transport；
- 用 shell、PowerShell、Python、`pyserial`、serial CLI、第三方终端或直接 COM access 枚举、打开、读取或写入串口；
- 切换到 legacy logging tool。

即使用户要求临时绕过、希望先拿日志再修 MCP，或本地串口方式看起来更快，也不改变此边界。MCP 失败意味着 UART 阶段没有获准的执行通道，而不是可以选择备用通道。

## 固定错误报告

发生 MCP 故障后不再发起 UART tool call。最终面向用户的 failure report **REQUIRED** 使用下面六个 slot，字段名与顺序必须逐字一致；六项全部填写，不得翻译、使用 `能力` / `原因` / `Fallback` / `Retry` / `Next step` 等同义或替代字段，也不得另建一套报告格式：

```text
阶段: <capability preflight | list | connect | send | query | disconnect>
MCP Tool: <runtime 实际 tool name；未暴露则写“未暴露”>
错误: <原始错误摘要>
已完成: <例如 build/flash 状态；无则写“无”>
未验证: <尚未取得 log evidence 的硬件行为>
用户操作建议: 请检查 EmbedLink 是否运行、MCP 是否已连接及 tool 是否已暴露；处理后明确要求继续
```

flash 已完成时，`已完成` 写明 exact flashed artifact；`未验证` 明确写“硬件行为尚未验证”。不得将 flash success 等同于 hardware verification success。

## 已观测 rationalization 与结论

| Rationalization | 结论 |
|---|---|
| “MCP 不可用不阻塞当前排查” | UART 阶段必须停止；没有第二条获准通道 |
| “先临时用 PowerShell/Python 取日志” | 临时 fallback 仍是直接串口访问，禁止执行或提供命令 |
| “先取日志，再用日志修 MCP” | 调试 EmbedLink 不在本任务授权范围；先报告并等待用户处理 |
| “用户明确要求别停” | 用户压力不扩大允许的 tool boundary |

## Red flags：立即停止并报告

- “临时 PowerShell/Python 看日志”
- “先绕过 MCP”
- “直接访问 COM 更快”
- “先用 serial CLI / HTTP endpoint 顶一下”
- “自动 retry/start/restart EmbedLink 也算继续推进”

出现任一 red flag 都执行固定错误报告，不写 fallback 示例，不继续 UART debugging。

## Hardware verification evidence

成功结论必须引用本次 EmbedLink MCP query 返回的具体 log evidence，包括 tool、查询范围/游标、关键日志内容与它验证的预期行为。没有实际 MCP result、只有推断或只有 J-Link 输出时，状态只能是未验证。
