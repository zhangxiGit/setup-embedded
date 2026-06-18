---
name: setup-embedded
description: Use when developing, debugging, building, or flashing embedded firmware projects. Invoke with `/setup-embedded` — auto-detects if first-time setup is needed. Triggers on requests to compile, build, flash, or test firmware changes on hardware. Supports Keil MDK (ARMCC), GCC, J-Link, ST-Link, OpenOCD.
---

# 嵌入式固件开发调试闭环

## 加载后

检查项目根目录的 `CLAUDE.md`（有则参考）和 `.claude/embedded-config.md`：

- **两者都不存在** → 配置向导：自动扫描工具链/调试器/工程文件 → 写入 `.claude/embedded-config.md`
- **配置存在** → 读取配置，等待开发任务

### rcw-tool 文档准备

每次加载时确保 rcw-tool 使用文档是最新的（不含程序源码，仅文档）：

```bash
DOCS_DIR="$HOME/.claude/rcw-tool-docs"
if [ -d "$DOCS_DIR/.git" ]; then
  cd "$DOCS_DIR" && git pull --ff-only 2>/dev/null
else
  git clone --depth 1 --branch master https://gitee.com/zhangxi95/zxx-log.git "$DOCS_DIR" 2>/dev/null
fi
```

加载后读取 `$HOME/.claude/rcw-tool-docs/README.md` 了解 rcw-tool 实际用法（以 README 为准，非 requirement 文档）。

### rcw-tool exe 路径

- 优先读 `.claude/embedded-config.md` 中的 `rcw-tool路径` 字段
- 若无，检查 `which rcw-tool 2>/dev/null`
- 若都找不到，询问用户提供路径，写入配置

---

## 配置向导

`.claude/embedded-config.md` 不存在时执行。每步先自动检测，检测不到才问用户。

**扫描编译工具链：**
```bash
for d in C D E F; do
  find "/$d" -maxdepth 4 -path "*/Keil*/UV4/UV4.exe" 2>/dev/null | head -1
done
which arm-none-eabi-gcc 2>/dev/null
```

**扫描调试探针：**
```bash
for d in C D E F; do
  find "/$d" -maxdepth 5 -path "*/Segger/JLink.exe" 2>/dev/null | head -1
done
which st-flash 2>/dev/null
```

**扫描工程文件：** `find . -maxdepth 3 -name "*.uvprojx" -o -name "CMakeLists.txt"`

**解析芯片型号：** 从 `.uvprojx` 的 `<Device>` 标签或 CMakeLists 的 `CMSIS COMPONENTS` 提取。

**烧录接口：** 默认 SWD。

**日志通道检测：**
- UART：检查 CLAUDE.md 或 `general.h` 中有无 UART 引脚定义（`TX`/`RX`/`USART`），有则记录波特率
- USB HID：检查源码中有无 `SUPPORT_REALTIME_LOG_PRINT`、`USB_REALTIME_LOG_ID`、VID/PID 定义
- 检测不到：配置段保留空模板，等 rcw-tool 后续支持

写入配置示例：
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

### 日志采集（rcw-tool）

rcw-tool 是独立的日志采集工具。源码在 `https://gitee.com/zhangxi95/zxx-log.git`（master 分支 = 文档，程序在另一分支），文档缓存在 `~/.claude/rcw-tool-docs/`。

exe 路径从 `.claude/embedded-config.md` 的 `rcw-tool路径` 读取。执行时用绝对路径：

```bash
RCWTOOL="<rcw-tool路径>"    # 从配置读取
```

#### 版本检查

每次使用前检查 rcw-tool 是否最新：

```bash
cd ~/.claude/rcw-tool-docs && git pull --ff-only 2>/dev/null
cat ~/.claude/rcw-tool-docs/CHANGELOG.md | head -20   # 查看最新版本
```

如果版本落后，告知用户更新。

#### 启动采集

```bash
$RCWTOOL monitor &
```

- 读 `.claude/embedded-config.md` 的 `## Tool A 日志` 段确定传输层参数
- 自动连接设备 + 写日志文件 + 启 Web UI（`http://localhost:8080`）
- 提示用户打开浏览器实时观察
- 如果设备刚烧录完/刚上电，monitor 会自动发 CONTROL_MSG 开启日志，第一行即为 `logDrvInit` 输出版本号

#### 手动控制日志开关（关键）

设备 `logDrvInit` 只执行一次（`gLogOnOff` 变为 1 后直接返回）。如果需重新抓取启动日志（含版本号）：

```bash
$RCWTOOL log off            # 关日志，重置 gLogOnOff=0
$RCWTOOL log on             # 重开日志 → 触发 logDrvInit → 输出版本号
```

`log on/off` 独立于 monitor，不需要 monitor 在跑。

#### 查看日志

```bash
$RCWTOOL tail -n 50               # 看最近日志
$RCWTOOL tail -f                  # 实时追踪（另开终端，Ctrl+C 退出）
$RCWTOOL grep "ERROR" -i -n 3     # 搜错误 + 上下文
$RCWTOOL grep "<关键信息>" -i     # 验证改动是否生效
$RCWTOOL grep "<关键信息>" -i --time 2m  # 最近2分钟内的匹配
$RCWTOOL info                     # 确认采集状态
```

> 完整 CLI 参考见 `~/.claude/rcw-tool-docs/README.md`。

#### 新一轮测试前

```bash
$RCWTOOL clear -f                 # 清旧日志，避免混淆
```

#### 停止采集

```bash
kill %1 或 pkill rcw-tool       # 停 monitor
```

### 完整闭环流程

```
1. 改代码
2. 编译 → 确认 "0 Error(s)"
3. 找 HEX → ls -t <HEX目录>/*.hex | head -1
4. 烧录 → J-Link 确认 "O.K." 无 "Skipped"
5. $RCWTOOL monitor &            # 启动日志采集
6. $RCWTOOL log off && $RCWTOOL log on   # 重置日志，抓版本号
7. $RCWTOOL tail -n 50           # 查看启动日志
8. $RCWTOOL grep "关键词" -i     # 验证改动
9. 没问题 → 报告用户验证结果
   有问题 → 分析日志 → 改代码 → clear -f → 回到步骤2
```

### rcw-tool 问题反馈

rcw-tool 本身有 bug 或功能不足时，**直接修改 rcw-tool 仓库的 CHANGELOG.md**（`E:\Elitech\Tools\ZxxLog\CHANGELOG.md`），按模板填充 BUG/FEAT 条目，然后 commit + push：

```bash
cd E:\Elitech\Tools\ZxxLog
# 编辑 CHANGELOG.md 中对应的条目
git add CHANGELOG.md && git commit -m "changelog: <简述>" && git push origin master
```

然后告知用户："CHANGELOG 有更新，请处理"，用户在 rcw-tool 终端说同样的话即可触发修复流程。

---

## 故障排查

| 现象 | 原因 | 处理 |
|------|------|------|
| 编译秒过但 HEX 没更新 | ARMCC5 增量编译不检测 `.h` 变更 | 删 .o/.axf/.bin，`-r` rebuild；验证 HEX 时间戳 > 源文件 |
| J-Link 输出 `Skipped. Contents already match` | HEX 与 Flash 一致，未执行编程 | 说明改动未生效，回退检查编译产物是否真的更新了 |
| 版本号改了但设备显示旧版本 | 编译产物实际未含新值 | `fromelf --text -s <target>.axf | grep <符号>` 查符号地址，grep HEX 验证字节 |
| HEX 文件名含旧版本号 | post-build 脚本用 .bin 中的版本号命名 | 文件名仅供参考，用内容为准；或直接用编译中间产物 |
| J-Link DAP 初始化失败 | 连接状态异常 | 设备断电再上电后重试 |
| SWD 锁死 | 用户程序禁用 SWD 引脚 | BOOT0=1 上电 → 擦除 → BOOT0=0 |
| rcw-tool 找不到设备 | USB 未插/VID:PID 不匹配 | 检查配置 + 设备连接 |
| rcw-tool 采集无输出 | 日志未开启/`gLogOnOff` 已为 1 | 先 `rcw-tool log off` 再 `rcw-tool log on` 重置 |
| rcw-tool monitor 启动失败 | exe 路径错误/端口占用 | 检查配置 `rcw-tool路径`；`taskkill //F //IM rcw-tool.exe` 清旧进程 |
| rcw-tool log on 后仍无输出 | 设备需断电上电 | 设备 USB HID 状态异常，断电再上电后重试 |
| 烧录后 HEX 没更新（Skipped） | 编译产物未变/增量编译 | 删 `.axf` `.bin` 后 `-r` rebuild，验证 HEX 时间戳 |
