# setup-embedded — Embedded Firmware Development & Debugging Skill

A Claude Code skill providing a complete debug closed-loop for embedded firmware: auto-discovery, cross-compilation, flashing, log capture, and verification.

## Recent Changes (2026-07)

**Log collection migrated from rcw-tool to EmbedLink (MCP protocol).** This is an architectural upgrade:

| Aspect | Old (rcw-tool) | New (EmbedLink) |
|--------|---------------|----------------|
| Protocol | CLI subcommands | MCP Tools (SSE transport) |
| Transport | USB HID | UART (MQTT supported, USB HID planned) |
| Log viewing | `tail -n N` / `tail -f` / `grep` | `query_logs` + agent-side filtering |
| Connection mgmt | `monitor &` background process | create → connect → query → disconnect lifecycle |
| Config format | `## Tool A 日志` (legacy, with `rcw-tool路径`) | `## 日志采集` (new format, with serial params) |
| Config migration | — | Auto-detect legacy format and prompt migration |
| Persistence | File-based | In-memory 10K ring buffer (persistence coming) |
| Real-time push | `tail -f` blocking read | Not yet supported; agent polls periodically |

## Supported Toolchains

### Compilers
- **Keil MDK (ARMCC)** — `UV4.exe` CLI build, supports `.uvprojx` projects
- **GCC (arm-none-eabi-gcc)** — CMake projects

### Debug Probes / Flashing
- **J-Link** — SWD interface, auto-generates `flash.jlink` script
- **ST-Link** — `st-flash` command line
- **OpenOCD** — Generic debug adapter

### Log Collection
- **EmbedLink** — Desktop app (Tauri), provides log collection via MCP Server at `127.0.0.1:3000`
- Transport: UART (primary), MQTT (supported)
- USB HID: planned for future release

## Workflow

### 1. First Use — Configuration Wizard

Auto-triggered when `.claude/embedded-config.md` is missing. Each step auto-detects first, only prompts user if detection fails:

1. Scan for compiler toolchains (Keil UV4.exe, arm-none-eabi-gcc)
2. Scan for debug probes (JLink.exe, st-flash)
3. Scan for project files (`.uvprojx`, `CMakeLists.txt`)
4. Extract chip model (from project file)
5. Detect log channel (search source for UART pin definitions and baud rate)
6. Call `list_serial_ports` to list available COM ports
7. Write `.claude/embedded-config.md`

Generated config structure:

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

### 2. Legacy Config Auto-Migration

If legacy `.claude/embedded-config.md` is detected (containing `rcw-tool路径` or `## Tool A 日志`), prompt for auto-migration:

- Remove `## Tool A 日志` section
- Migrate UART params to new `## 日志采集` section
- Preserve USB HID params as comments, annotated "EmbedLink 后续版本支持"
- Keep `## 编译` and `## 烧录` sections unchanged

### 3. Dev Closed Loop

```
1. Edit code
2. Verify EmbedLink health → curl http://127.0.0.1:3000/health
3. Build → verify build.log contains "0 Error(s)"
4. Find HEX → ls -t <HEX dir>/*.hex | head -1
5. Flash → J-Link confirms "O.K." without "Skipped"
6. create_uart_connection → record connection_id → connect
7. send_serial_data to send control commands (if reset/log enable needed)
8. query_logs (limit=50) → inspect boot logs
9. Analyze display_text → verify changes
   All good → report results to user
   Issues found → analyze logs → edit code → rebuild connection → back to step 3
```

### 4. EmbedLink Load Flow

Executed on each `/setup-embedded` invocation:

1. **Health check** — `curl -s http://127.0.0.1:3000/health`, expect `ok`
2. **Health check fails** → prompt user to start EmbedLink (`cargo tauri dev` or desktop shortcut)
3. **Health check passes** → verify MCP tools available (call `list_connections`)
4. **MCP not configured** → prompt to add to `.mcp.json`: `{"embedlink": {"type": "sse", "url": "http://127.0.0.1:3000/mcp"}}`

## EmbedLink MCP Tools Quick Reference

### Core Tools

| MCP Tool | Purpose | Key Parameters |
|----------|---------|---------------|
| `list_serial_ports` | List available COM ports | — |
| `create_uart_connection` | Create UART connection | `port_name`, `baud_rate`, `data_bits`, `stop_bits`, `parity`, `flow_control` |
| `connect` | Open connection, start receiving | `connection_id` |
| `disconnect` | Close connection (reusable) | `connection_id` |
| `delete_connection` | Delete connection permanently | `connection_id` |
| `update_connection` | Modify connection config | `connection_id` + fields to change |
| `query_logs` | View logs | `connection_id` (optional), `limit` (default 100, max 10000) |
| `send_serial_data` | Send control commands to device | `connection_id`, `data`, `format` (`"hex"` or `"ascii"`) |
| `list_connections` | View all connection statuses | — |

### MQTT Tools (Supported)

| MCP Tool | Purpose |
|----------|---------|
| `create_mqtt_connection` | Create MQTT connection |
| `send_mqtt_message` | Send MQTT message |
| `mqtt_subscribe` / `mqtt_unsubscribe` | Subscribe/unsubscribe MQTT topics at runtime |

### App Settings

| MCP Tool | Purpose |
|----------|---------|
| `get_settings` | Read EmbedLink settings (theme, log level, MCP port, etc.) |
| `save_settings` | Modify and save EmbedLink settings |

## rcw-tool → EmbedLink Command Mapping

| rcw-tool Command | EmbedLink Equivalent |
|-----------------|---------------------|
| `monitor &` | `create_uart_connection` + `connect` |
| `log on` / `log off` | `send_serial_data` (control commands depend on firmware protocol) |
| `tail -n N` | `query_logs` (`limit: N`) |
| `tail -f` | Periodically poll `query_logs` |
| `grep "keyword"` | Agent filters `display_text` from `query_logs` results |
| `clear -f` | `disconnect` → `delete_connection` → recreate + `connect` |
| `info` | `list_connections` + `query_logs` |
| `kill %1` | `disconnect` |

## EmbedLink Known Gaps

| Feature | Status | Workaround |
|---------|--------|-----------|
| Text search | No server-side filter in `query_logs` | Agent filters JSON locally |
| Time range filter | Only `connection_id` + `limit` | Agent filters by `timestamp` |
| Clear logs | No standalone `clear` command | Recreate connection |
| Real-time push | Request-response mode | Agent polls periodically |
| Data persistence | In-memory 10K ring buffer | Export periodically |
| USB HID support | UART / MQTT only | Coming in future release |
| Firmware flashing | MCP tool is placeholder | Continue using J-Link/ST-Link/OpenOCD CLI |
| MCP port config | Hardcoded to 3000 | No change needed yet |

## Troubleshooting

### Build
| Symptom | Fix |
|---------|-----|
| Build succeeds instantly but HEX unchanged | ARMCC5 doesn't detect `.h` changes → delete `.axf`/`.bin`, `-r` rebuild |
| Version number changed but device shows old version | `fromelf --text -s <target>.axf \| grep <symbol>` to verify |

### Flash
| Symptom | Fix |
|---------|-----|
| J-Link `Skipped` | Change didn't take effect; verify build output actually updated |
| J-Link DAP init failed | Power-cycle device and retry |
| SWD locked | BOOT0=1 power on → erase → BOOT0=0 |

### EmbedLink
| Symptom | Fix |
|---------|-----|
| Health check `Connection refused` | Start EmbedLink (`cargo tauri dev` or desktop shortcut) |
| `list_serial_ports` returns empty | Check USB cable; verify CH340/CP210x driver installed |
| `connect` fails | Close Putty/serial monitor; check device is powered on |
| `query_logs` returns nothing | Check baud rate; use `send_serial_data` to trigger log output |
| `send_serial_data` gets no response | Verify command format matches firmware protocol; try ASCII/hex switch |
| Large volume of stale data | Recreate connection: `disconnect` → `delete_connection` → recreate + `connect` |
| MCP Tool returns "Unknown tool" | Check `.mcp.json` for embedlink SSE config |
| No boot logs after flash | Wait 2-3 seconds then query; or `send_serial_data` to actively trigger |

## File Structure

```
setup-embedded/
├── SKILL.md                # Claude Code skill definition (loaded at runtime)
├── embedlink-reference.md  # EmbedLink MCP Tool detailed reference
├── README.md               # Entry point (this file)
├── README_CN.md            # Chinese documentation
├── README_EN.md            # English documentation
└── SKILL.md.bak            # Legacy backup (rcw-tool version, gitignored)
```

## Dependencies

- **EmbedLink** desktop app (must run locally, listening on `127.0.0.1:3000`)
- Claude Code MCP config (`.mcp.json` or global `mcp.json`)
- Compiler toolchain and debug probe (as needed per project)
