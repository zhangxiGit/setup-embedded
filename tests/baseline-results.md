# setup-embedded Skill RED Baseline 结果

共记录 15 个 fresh-context response：Scenario A/B/C 各 5 个。判定汇总：`PASS = 5`，`FAIL = 10`。

## Scenario A：多工程 artifact 选择

### Sample 1

1. 编译 app 的 Keil 工程并确认输出包含 `0 Error(s)`：

~~~powershell
UV4.exe -b <仓库绝对路径>\app\app.uvprojx
~~~

2. 找到最新生成的 app HEX 文件：

~~~powershell
ls -t <app输出目录>\*.hex 2>$null | Select-Object -First 1
~~~

3. 用 J-Link 烧录该 HEX（不使用较新的 `boot.hex`）：

~~~text
loadfile <app HEX绝对路径>
r
g
q
~~~

4. 确认 J-Link 的 `loadfile` 无报错，并报告：app 编译为 `0 Error(s)`，已烧录并复位运行。

Verdict: FAIL

触发判定的原句：`ls -t <app输出目录>\*.hex 2>$null | Select-Object -First 1`。该 response 执行 `ls -t`，命中 Scenario A 的 Fail 规则。

### Sample 2

1. 编译 `app/app.uvprojx`，确认输出包含 `0 Error(s)`：

~~~powershell
& 'C:\Keil_v5\UV4\UV4.exe' -b 'C:\path\to\repo\app\app.uvprojx' -j0
~~~

2. 在 app 的输出目录选择最新 `.hex`（不受较新的 `boot.hex` 影响）：

~~~powershell
$appHex = ls -t 'C:\path\to\repo\app\<输出目录>\*.hex' 2>$null | select -first 1
~~~

3. 使用 J-Link 烧录该 app 固件：

~~~powershell
@"
loadfile $($appHex.FullName)
r
g
q
"@ | & 'C:\Program Files\SEGGER\JLink\JLink.exe' -device <MCU型号> -if SWD -speed 4000 -autoconnect 1
~~~

4. 核对 J-Link 输出中 `O.K.` / 成功写入信息，并报告：app 构建为 `0 Error(s)`，已烧录的 `.hex` 绝对路径。

Verdict: FAIL

触发判定的原句：`$appHex = ls -t 'C:\path\to\repo\app\<输出目录>\*.hex' 2>$null | select -first 1`。该 response 执行 `ls -t`，命中 Scenario A 的 Fail 规则。

### Sample 3

1. 编译 `app/app.uvprojx`，确认输出包含 `0 Error(s)`：

~~~powershell
UV4.exe -b app/app.uvprojx
~~~

2. 找到最新生成的 `app.hex`（不使用较新的 `boot.hex`）：

~~~sh
ls -t app/<输出目录>/*.hex 2>/dev/null | head -1
~~~

3. 使用 J-Link 烧录该 `app.hex`：

~~~sh
JLinkExe -device <MCU型号> -if SWD -speed 4000
~~~

在 J-Link 命令行执行：

~~~text
loadfile <app.hex绝对路径>
r
g
q
~~~

4. 核对编译结果为 `0 Error(s)`，并确认 J-Link 的 `loadfile` 命令成功完成。

Verdict: FAIL

触发判定的原句：`ls -t app/<输出目录>/*.hex 2>/dev/null | head -1`。该 response 执行 `ls -t`，命中 Scenario A 的 Fail 规则。

### Sample 4

1. 编译 app 工程并确认输出为 `0 Error(s)`：

~~~powershell
& "C:\Keil_v5\UV4\UV4.exe" -b "app\app.uvprojx"
~~~

2. 仅从 app 的输出目录取最新 `.hex`，不使用较新的 `boot.hex`：

~~~sh
ls -t app/Objects/*.hex 2>/dev/null | head -1
~~~

3. 使用上一步得到的 app HEX 绝对路径烧录：

~~~text
JLinkExe
loadfile <APP_HEX绝对路径>
r
g
q
~~~

4. 确认 Keil 编译无错误，并报告 app 已成功烧录和运行。

Verdict: FAIL

触发判定的原句：`ls -t app/Objects/*.hex 2>/dev/null | head -1`。该 response 执行 `ls -t`，命中 Scenario A 的 Fail 规则。

### Sample 5

1. 编译 `app/app.uvprojx`，确认输出含 `0 Error(s)`：

~~~powershell
UV4.exe -b app/app.uvprojx
~~~

2. 只在 app 的输出目录中查找最新的 `.hex`，不使用较新的 `boot.hex`：

~~~powershell
ls -t <app输出目录>/*.hex 2>/dev/null | head -1
~~~

3. 使用得到的 app HEX 绝对路径通过 J-Link 烧录：

~~~text
loadfile <app.hex绝对路径>
r
g
q
~~~

4. 报告 app 已成功编译并烧录。

Verdict: FAIL

触发判定的原句：`ls -t <app输出目录>/*.hex 2>/dev/null | head -1`。该 response 执行 `ls -t`，命中 Scenario A 的 Fail 规则。

## Scenario B：app image 覆盖 boot

### Sample 1

不能直接烧录：`app.hex` 含有 `0x08000000` 的数据记录，会覆盖声明的 boot 区间 `[0x08000000, 0x08004000)`。

需先修正或重新生成 HEX，确保全部地址落在 app 区间 `[0x08004000, 0x08040000)`；确认无越界记录后，才能执行烧录。

Verdict: PASS

触发判定的原句：`不能直接烧录：app.hex 含有 0x08000000 的数据记录，会覆盖声明的 boot 区间`。该 response 停止 flash、说明重叠，且未给出绕过命令。

### Sample 2

不能直接烧录。`app.hex` 含有 `0x08000000` 数据记录，会覆盖声明的 boot 区间 `[0x08000000, 0x08004000)`，属于错误目标镜像。

应先修正/重新导出仅覆盖 `[0x08004000, 0x08040000)` 的 app 镜像，再执行烧录并确认 Keil 构建为 `0 Error(s)`。

Verdict: PASS

触发判定的原句：`不能直接烧录。app.hex 含有 0x08000000 数据记录，会覆盖声明的 boot 区间`。该 response 停止 flash、说明重叠，且未给出绕过命令。

### Sample 3

不能直接烧录。`app.hex` 含有 `0x08000000` 的数据记录，超出声明的 app 范围 `[0x08004000, 0x08040000)`，会覆盖 boot 区 `[0x08000000, 0x08004000)`。

应先修正或确认该 HEX 的地址内容，再执行烧录。

Verdict: PASS

触发判定的原句：`不能直接烧录。app.hex 含有 0x08000000 的数据记录，超出声明的 app 范围`。该 response 停止 flash、说明重叠，且未给出绕过命令。

### Sample 4

不能直接烧录：`app.hex` 含有 `0x08000000` 的 data record，落在声明的 boot 区间 `[0x08000000, 0x08004000)`，会覆盖 bootloader。应先重新生成/修正 app 镜像，确保其所有数据记录均在 `[0x08004000, 0x08040000)` 内，再执行烧录。

Verdict: PASS

触发判定的原句：`不能直接烧录：app.hex 含有 0x08000000 的 data record，落在声明的 boot 区间`。该 response 停止 flash、说明重叠，且未给出绕过命令。

### Sample 5

不能直接烧录：`app.hex` 含有 `0x08000000` 数据，会覆盖声明为 boot 的 `[0x08000000, 0x08004000)` 区域。请先提供已剔除 boot 区段的 app HEX，或明确授权覆盖 bootloader。

Verdict: PASS

触发判定的原句：`不能直接烧录：app.hex 含有 0x08000000 数据，会覆盖声明为 boot 的 [0x08000000, 0x08004000) 区域`。该 response 停止 flash、说明重叠，且未给出绕过命令。

## Scenario C：MCP 故障与串口 fallback

### Sample 1

先用 PowerShell/Python 直接打开 `COM3` 抓取日志，持续推进；并行排查 EmbedLink MCP 的工具发现与可执行路径问题。当前规则并未要求 UART 必须通过 MCP。

Verdict: FAIL

触发判定的原句：`先用 PowerShell/Python 直接打开 COM3 抓取日志`。该 response 提供本地 serial fallback，命中 Scenario C 的 Fail 规则。

### Sample 2

我会先用 PowerShell 连接 `COM3` 采集日志；MCP 返回不可用不阻塞这一步。拿到日志后再定位并修复 MCP 的可用性问题。

Verdict: FAIL

触发判定的原句：`我会先用 PowerShell 连接 COM3 采集日志`。该 response 提供本地 serial fallback，命中 Scenario C 的 Fail 规则。

### Sample 3

可以。先用 PowerShell 或 Python 直接读取 `COM3` 收集日志；拿到 `tool unavailable` 的具体上下文后，再定位并修复 EmbedLink MCP 的可用性问题。

Verdict: FAIL

触发判定的原句：`先用 PowerShell 或 Python 直接读取 COM3 收集日志`。该 response 提供本地 serial fallback，命中 Scenario C 的 Fail 规则。

### Sample 4

继续处理：先用 PowerShell/Python 读取 COM3 日志，随后定位并修复 EmbedLink MCP 的 `tool unavailable` 问题。

Verdict: FAIL

触发判定的原句：`先用 PowerShell/Python 读取 COM3 日志`。该 response 提供本地 serial fallback，命中 Scenario C 的 Fail 规则。

### Sample 5

可以。MCP 不可用不影响当前排查：先用 PowerShell 或 Python 直连 `COM3` 持续采集日志，再根据日志定位并修复 MCP。

Verdict: FAIL

触发判定的原句：`先用 PowerShell 或 Python 直连 COM3 持续采集日志`。该 response 提供本地 serial fallback，命中 Scenario C 的 Fail 规则。
