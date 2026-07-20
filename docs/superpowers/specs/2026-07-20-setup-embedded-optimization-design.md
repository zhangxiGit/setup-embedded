# setup-embedded 双平台优化设计

## 目标

将 `setup-embedded` 优化为 Codex 与 Claude Code 共用的嵌入式开发 skill，首版聚焦 Windows、Keil MDK、J-Link 与 UART。日志和设备调试统一通过 EmbedLink MCP 完成；本地 PowerShell 仅用于工具检测、工程解析、build、firmware image 校验和调用 J-Link 烧录。

本次优化重点解决两类高风险问题：

1. 多工程仓库中误选 bootloader HEX，或 app image 地址错误而覆盖 bootloader。
2. EmbedLink MCP 不可用时，Agent 私自通过 PowerShell、Python 或串口 CLI 访问 COM 端口。

## 非目标

- 首版不承诺 GCC、ST-Link、OpenOCD、USB HID 或 MQTT 的完整支持。
- EmbedLink MCP 不负责 build 或 flash；Keil 与 J-Link 继续作为本地工具运行。
- 不再支持 rcw-tool，也不保留 rcw-tool 文档同步、CLI 映射或外部仓库写入流程。
- 不实现 PowerShell 串口访问、备用日志后端或 EmbedLink 自动启动/重启。

## 仓库结构

```text
setup-embedded/
├── SKILL.md
├── README.md
├── agents/
│   └── openai.yaml
├── scripts/
│   ├── discover-embedded.ps1
│   └── verify-firmware-image.ps1
├── references/
│   ├── embedlink-mcp.md
│   └── keil-jlink.md
└── tests/
    ├── fixtures/
    └── run-tests.ps1
```

- `SKILL.md`：保留触发条件、决策流程、安全规则和开发闭环，具体命令下沉到 references。
- `scripts/discover-embedded.ps1`：检测 `UV4.exe`、`JLink.exe`、`.uvprojx`、target、scatter file 和构建产物。
- `scripts/verify-firmware-image.ps1`：解析 Intel HEX，并在 flash 前验证地址范围。
- `references/embedlink-mcp.md`：定义 EmbedLink MCP UART 操作、MCP-only 边界和故障报告格式。
- `references/keil-jlink.md`：定义 Keil build 和 J-Link flash 的 Windows 流程。
- `agents/openai.yaml`：提供 Codex UI metadata；Claude Code 直接使用同一份 `SKILL.md`。
- `README.md`：使用中文为主、technical terms 保留 English 的双平台安装与使用说明。

现有 `README_CN.md` 和 `README_EN.md` 在内容迁移到 `README.md` 后删除，避免三份文档漂移。

## 双平台与统一配置

Codex 和 Claude Code 共用 `.embedded/embedded-config.md`。skill 根据当前 runtime 读取适用的 `AGENTS.md` 或 `CLAUDE.md`，但 build、flash、Flash layout 和 UART 配置只维护一份。

配置至少包含：

```markdown
# Embedded 开发配置

## Build
- Tool: Keil MDK
- UV4Path: ...
- AppProject: ...
- AppTarget: ...
- AppArtifact: ...
- BootProject: ...
- BootTarget: ...
- BootArtifact: ...

## FlashLayout
- BootStart: ...
- BootEndExclusive: ...
- AppStart: ...
- AppEndExclusive: ...
- AppStartEraseBoundaryConfirmed: true

## Flash
- Tool: J-Link
- JLinkPath: ...
- Device: ...
- Interface: SWD
- SpeedKHz: 4000

## Debug
- Tool: EmbedLink MCP
- Transport: UART
- Port: ...
- BaudRate: ...
- DataBits: 8
- StopBits: one
- Parity: none
- FlowControl: none
```

字段名保持稳定，地址统一使用十六进制。`connection_id` 属于 runtime state，不写入配置。

## 旧配置迁移

加载时检测 `.Codex/embedded-config.md` 与 `.claude/embedded-config.md`：

1. 展示可迁移字段，并请求用户确认。
2. 迁移有效的 Keil、J-Link、project 和 UART 参数。
3. 忽略 `rcw-tool路径`、`Tool A 日志` 等 rcw-tool 专属字段。
4. 重新执行 boot/app 识别和 Flash layout 确认，不信任旧配置中的隐式推断。
5. 写入 `.embedded/embedded-config.md`，旧文件原样保留。

迁移过程不自动删除或覆盖旧文件。

## 工具和工程发现

`discover-embedded.ps1` 输出结构化 JSON，供两个 runtime 使用。脚本只检查 workspace、`PATH`、已知安装位置和用户显式提供的搜索根，不递归扫描整个磁盘。

发现顺序：

1. 定位 `UV4.exe` 与 `JLink.exe`。
2. 在 workspace 内枚举 `.uvprojx`。
3. 解析 project、target、output、IROM 和 scatter file 配置。
4. 基于 linker address range 判断 boot/app 候选；project 或 target 名称仅作为辅助信号。
5. 将候选映射展示给用户确认，再写入统一配置。

脚本不得枚举、打开、读取或写入 COM 端口，也不得引用串口 library。

## Bootloader 识别与保护模型

### 初始识别

仓库预期同时存在 boot 与 app 两个 Keil 工程。自动识别只生成候选，不直接授权 flash。

Flash layout 的信息来源按可信度排序：

1. 用户确认后的 `.embedded/embedded-config.md`。
2. scatter file 中的 load/execution region。
3. `.uvprojx` 的 IROM start/size。
4. project/target 名称中的 `boot`、`loader`、`app` 等关键词，仅用于提示。

不同来源冲突时执行 fail closed：停止 flash，展示冲突并要求用户确认。

### Artifact 绑定

build 和 flash 必须绑定到明确的 project、target 与 output artifact。禁止通过修改时间从仓库内所有 HEX 中选择“最新文件”。

默认目标始终为 app。build 完成后确认：

- Keil 返回成功且 build log 为 `0 Error(s)`。
- 配置绑定的 app artifact 存在。
- artifact 修改时间晚于本次 build 开始时间。

### Intel HEX 校验

`verify-firmware-image.ps1` 解析 Intel HEX data record、extended segment address 和 extended linear address，生成实际数据地址区间。

app 模式下，以下任一条件成立即停止 flash：

- HEX 为空、格式无效、checksum 错误或地址无法解析。
- 任一数据区间与 `[BootStart, BootEndExclusive)` 重叠。
- 任一数据区间落在 `[AppStart, AppEndExclusive)` 之外。
- linker、scatter file、统一配置或 HEX 地址范围互相冲突。
- `AppStartEraseBoundaryConfirmed` 不是 `true`。

`.bin` 不携带 load address。首版默认拒绝直接 flash `.bin`；只有配置明确记录并经用户确认的 load address 与允许范围时才可校验和使用。

### J-Link 安全规则

- J-Link command file 只能引用刚通过校验的确切 artifact。
- 禁止生成 `erase`、chip erase 或 mass erase 命令。
- 校验失败后不得提供绕过命令继续 flash。
- J-Link 返回失败、`Skipped` 或无法证明实际写入时，不得报告 flash 成功。

### Boot 模式

只有用户明确要求烧录 bootloader，且在执行前完成二次确认，才允许进入 boot 模式。boot artifact 必须绑定到配置中的 boot project/target，并完全落在 boot 允许范围内；否则停止。

## EmbedLink MCP-only 调试边界

UART port list、connection、disconnect、send 和 log query 全部通过 EmbedLink MCP Tool 完成。

以下方式一律不作为调试 fallback：

- PowerShell COM API、`mode` 或 registry 串口操作
- Python、`pyserial` 或临时脚本
- 串口 CLI 和第三方终端程序
- rcw-tool
- 直接 HTTP health endpoint

PowerShell 只能用于工具发现、project 解析、Keil build、firmware image 校验和 J-Link flash。

### MCP 失败处理

- 仅 build：无需 EmbedLink MCP。
- 仅 flash：通过 boot 安全门后可调用 J-Link，不隐式开始 UART 调试。
- debug、hardware test 或完整闭环：开始前调用一次无副作用的 EmbedLink MCP 能力检查。
- MCP Tool 缺失或调用失败：立即停止调试并报告；不自动重试、不启动或重启 EmbedLink、不切换 fallback。
- flash 后发生 MCP 故障：报告“已烧录，但硬件行为尚未验证”，不得宣称闭环成功。

故障报告包含：失败阶段、MCP Tool、错误内容、已完成状态、尚未验证内容，以及需要用户检查 EmbedLink 的建议。

## 开发闭环

```text
识别任务类型
→ 加载、迁移或生成统一配置
→ 选择确切 app project 与 target
→ Keil build
→ 验证 build result 与 app artifact freshness
→ 解析 HEX 并通过 boot 安全门
→ J-Link flash 确切 artifact
→ 仅通过 EmbedLink MCP 获取 UART 日志
→ 根据日志证据报告 hardware verification 结果
```

如果用户只请求其中一个阶段，仅执行该阶段所需的前置检查，不擅自扩大范围。

## Error handling

所有安全相关错误采用 fail closed：

| 条件 | 行为 |
|---|---|
| boot/app 识别不确定 | 停止并请求确认 |
| Flash layout 来源冲突 | 停止并展示冲突 |
| artifact 与选定 target 不匹配 | 停止 build/flash 流程 |
| HEX 地址覆盖 boot 或越界 | 停止，不生成 J-Link command file |
| erase boundary 未确认 | 停止并请求确认 |
| EmbedLink MCP 不可用 | 停止调试并立即报告 |
| flash 成功但日志未验证 | 报告部分完成，不宣称闭环成功 |

## 测试策略

### Script fixtures

`tests/run-tests.ps1` 使用本地 fixtures 覆盖：

- 同时存在 boot/app 两个 `.uvprojx`。
- 仓库中 boot HEX 比 app HEX 更新，但仍必须选择 app artifact。
- Intel HEX extended linear address 与 extended segment address。
- app HEX 与 boot range 重叠。
- app HEX 超出允许范围。
- checksum 错误、空 HEX 和 malformed record。
- `.bin` 缺少 load address。
- scatter、IROM 和统一配置冲突。
- boot 模式缺少明确请求或二次确认。

### Skill RED-GREEN forward tests

修改前建立 baseline，记录 Agent 在以下场景中的实际失败行为：

1. 多个 HEX 存在时误选最新文件。
2. app HEX 覆盖 boot range 时仍继续 flash。
3. EmbedLink MCP 失败时尝试 PowerShell/Python 串口 fallback。

修改后用相同场景验证：

- 选择配置绑定的 app artifact。
- 危险或不确定的 flash 全部 fail closed。
- MCP 失败后立即报告且不访问 COM。

### Static validation

- 使用 `quick_validate.py` 校验 skill frontmatter 和目录命名。
- 校验 `agents/openai.yaml` 与 `SKILL.md` 一致。
- 校验 Markdown references 和本地链接。
- 检查 PowerShell 脚本中不存在串口访问实现。

当前会话未暴露 EmbedLink MCP Tool，因此本轮只能验证 MCP 调用策略和失败行为，不能宣称完成真实 UART hardware integration test。最终交付必须明确该限制。

## 验收标准

- Codex 与 Claude Code 使用同一份 `SKILL.md` 和 `.embedded/embedded-config.md`。
- 文档和 skill 中不再出现 rcw-tool 操作流程。
- 默认 build/flash 只针对配置绑定的 app project/target/artifact。
- 任意可能覆盖 bootloader 的 image 都在 J-Link 执行前被阻止。
- bootloader flash 需要明确请求与二次确认。
- UART 调试只使用 EmbedLink MCP，MCP 故障时不存在本地串口 fallback。
- 自动化 tests 和 static validation 通过。
- 未执行的真实硬件验证不会被表述为已完成。
