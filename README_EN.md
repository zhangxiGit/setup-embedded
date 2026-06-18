# setup-embedded — Embedded Firmware Dev Loop for Claude Code

A Claude Code skill for embedded firmware development, covering the full **Build → Flash → Log Capture** loop. Supports Keil MDK (ARMCC), GCC, J-Link, ST-Link, OpenOCD, and integrates with [rcw-tool](https://gitee.com/zhangxi95/zxx-log) for real-time log collection.

## Features

| Phase | Capability |
|-------|------------|
| **Setup Wizard** | Auto-detect Keil/ARMCC/GCC/J-Link/ST-Link paths, parse MCU model and project files |
| **Build** | Compile via Keil UV4 or GCC, auto-verify "0 Error(s)", handle incremental build issues |
| **Flash** | Support J-Link / ST-Link / OpenOCD, auto-generate flash scripts and verify results |
| **Log Capture** | Integrated rcw-tool: USB HID / UART real-time logging, version verification, log search & tail |

## Dependencies

### Required: rcw-tool

The log capture and device diagnostic features require **rcw-tool**.

| Item | URL |
|------|-----|
| Repository | [https://gitee.com/zhangxi95/zxx-log](https://gitee.com/zhangxi95/zxx-log) |
| Branches | `master` — documentation; program binaries on other branches |

```bash
# Clone rcw-tool docs (the skill handles this automatically, manual fallback)
git clone --depth 1 --branch master https://gitee.com/zhangxi95/zxx-log.git ~/.claude/rcw-tool-docs
```

> The rcw-tool executable is distributed separately (not open source). Contact the author or download from the project's release page.

### Optional: Build & Flash Toolchains

- **Keil MDK** (UV4) — ARMCC toolchain
- **GCC** (`arm-none-eabi-gcc`) — Open-source ARM toolchain
- **J-Link** (Segger) — Debug probe
- **ST-Link** (`st-flash`) — STM32 debug probe
- **OpenOCD** — Open-source debug utility

Install only what you need — the skill auto-detects available tools on first run.

## Installation

### Option 1: Via Claude Code Plugin Marketplace (Recommended)

```bash
claude plugins install setup-embedded
```

### Option 2: Manual Install

```bash
# 1. Clone the repository
git clone https://github.com/zhangxiGit/setup-embedded.git

# 2. Copy to Claude Code skills directory
cp -r setup-embedded ~/.claude/skills/setup-embedded

# 3. Restart Claude Code or run
claude /setup-embedded
```

### Option 3: Copy SKILL.md Only

If you only need the core definition file:

```bash
mkdir -p ~/.claude/skills/setup-embedded
cp SKILL.md ~/.claude/skills/setup-embedded/
```

## Usage

### First Run: Setup Wizard

Open Claude Code in your embedded project root and run:

```
/setup-embedded
```

The first run triggers the **setup wizard**:

1. **Scan toolchains** — Auto-detect Keil UV4 on drives C-F and `arm-none-eabi-gcc`
2. **Scan debug probes** — Auto-detect J-Link, ST-Link paths
3. **Scan project files** — Find `.uvprojx` or `CMakeLists.txt`
4. **Parse MCU model** — Extract chip model from project files
5. **Detect log channel** — Auto-identify UART or USB HID log parameters

Items that can't be auto-detected will prompt the user. Configuration is saved to `.claude/embedded-config.md`.

### Dev Loop

```
1. Edit code
2. Build → Confirm "0 Error(s)"
3. Find HEX → Flash binary
4. Flash → Confirm "O.K."
5. Start log capture → rcw-tool monitor &
6. Reset logs → rcw-tool log off && rcw-tool log on
7. View boot logs → rcw-tool tail -n 50
8. Verify changes → rcw-tool grep "keyword" -i
```

### rcw-tool Quick Reference

```bash
rcw-tool monitor &                  # Start log capture (background, Web UI at localhost:8080)
rcw-tool log off && rcw-tool log on # Reset log state, capture full boot log
rcw-tool tail -n 50                 # Show last 50 log lines
rcw-tool tail -f                    # Follow logs in real time (Ctrl+C to exit)
rcw-tool grep "keyword" -i          # Search logs
rcw-tool grep "ERROR" -i -n 3       # Search errors with context
rcw-tool grep "keyword" -i --time 2m # Search within last 2 minutes
rcw-tool clear -f                   # Clear old logs (before a new test round)
rcw-tool info                       # Show capture status
pkill rcw-tool                      # Stop capture
```

## Supported Hardware

- STM32 series (L4 / F4 / WL / G0 / H7, etc.)
- nRF52 / nRF53 series
- ESP32 series
- RP2040 (planned)

## Config Example

Generated `.claude/embedded-config.md`:

```markdown
# Embedded Debug Configuration
## Build
- Toolchain: Keil
- UV4 Path: D:/Keil_v5/UV4/UV4.exe
- Project File: Keil/xxx.uvprojx
- HEX Directory: Keil/
## Flash
- Tool: JLink
- JLink Path: D:/Keil_v5/ARM/Segger/JLink.exe
- MCU Model: STM32L452VC
- Interface: SWD
- Speed: 4000
## Tool A Log
Transport: USB_HID
VID: 0x04D8
PID: 0x0360
Log msgID: 0x800E
Enable Log: CONTROL_MSG
rcw-tool Path: C:/Tools/rcw-tool/rcw-tool.exe
```

## License

MIT

## Author

zhangxiGit — Built with Claude Code
