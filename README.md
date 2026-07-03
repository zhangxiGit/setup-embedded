# setup-embedded — Claude Code Embedded Dev Skill

[中文文档](README_CN.md) | [English Docs](README_EN.md)

A Claude Code skill for embedded firmware development: **Build → Flash → Log Capture** closed-loop debugging.

Supports Keil MDK (ARMCC), GCC, J-Link, ST-Link, OpenOCD. Uses [EmbedLink](https://github.com/zhangxiGit/embedlink) desktop app for log collection via MCP.

## Quick Install

```bash
# Clone into Claude Code skills directory
git clone https://github.com/zhangxiGit/setup-embedded.git ~/.claude/skills/setup-embedded
```

Then in Claude Code: `/setup-embedded`

## What's New (2026-07)

Log collection migrated from **rcw-tool** (CLI) to **EmbedLink** (MCP protocol). See the changelog in [README_CN.md](README_CN.md) or [README_EN.md](README_EN.md).

---

详细说明请查阅：[README_CN.md](README_CN.md) | [README_EN.md](README_EN.md)
