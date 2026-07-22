# Keil MDK 与 J-Link Windows 操作规范

## Exact binding

默认只使用 `.embedded/embedded-config.md` 中同一组 `AppProject`、`AppTarget`、`AppArtifact`。用户明确请求 boot 且完成第二次确认后，才切换到同一组 `BootProject`、`BootTarget`、`BootArtifact`。所有路径在 workspace 内解析为 absolute path；identity 不完整或冲突时停止。

## Keil exact project/target build

记录 build 开始时间，然后调用配置中的 exact `UV4Path`、project 与 target，例如：

```powershell
& <UV4Path> -b <ProjectAbsolutePath> -t <ExactTargetName> -j0 -o <BuildLogAbsolutePath>
```

只有以下三项同时满足才算 build success：

1. `UV4.exe` process exit code 为 `0`；
2. build log 明确包含 `0 Error(s)`；
3. 配置绑定的 exact artifact 存在，且 `LastWriteTime` 晚于本次 build 开始时间。

产物结果采用正向 contract：`Project`、`Target`、`Artifact` 三项逐项回显，后续 guard 与 `loadfile` 沿用该 exact `Artifact`。不要通过仓库或目录扫描重新选择 HEX。

## REQUIRED firmware image guard

在创建任何 J-Link command file 前运行 guard。app 示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-firmware-image.ps1 `
  -ImagePath <AppArtifactAbsolutePath> -Mode app `
  -BootStart <BootStart> -BootEndExclusive <BootEndExclusive> `
  -AppStart <AppStart> -AppEndExclusive <AppEndExclusive> `
  -AppStartEraseBoundaryConfirmed
```

boot 模式还必须有用户明确请求与第二次确认，并传入 `-Mode boot -BootFlashConfirmed`。只有 guard process exit 0 且输出 JSON 的 `safe` 为 `true` 才能继续。必须先向用户展示完整 safe JSON，随后才创建包含 `loadfile` 的 command file。unsafe、解析失败、边界冲突或信息不全时停止，不提供绕过命令。

## J-Link command file

command file 不得包含 `erase`、chip erase 或 mass erase。固定格式示例：

```text
device STM32L452VC
si SWD
speed 4000
loadfile C:\firmware\app\Objects\app.hex
r
g
q
```

示例中的 artifact 仅表示格式；实际 `loadfile` 必须使用刚通过 guard 的 exact resolved artifact。

### 临时文件安全

1. 在 workspace 内选定一个明确文件名，将其解析为 absolute path。
2. 验证 resolved command-file path 仍位于 resolved workspace path 内。
3. 仅在 safe guard JSON 已展示后写入命令。
4. 以配置中的 exact `JLinkPath` 调用 `JLink.exe -NoGui 1 -ExitOnError 1 -CommandFile <ResolvedCommandFile>`。
5. 在 `finally` 中只删除该 exact resolved command file；不得用 glob、递归删除或清理整个目录。

J-Link process 非 exit 0、输出含 `Skipped`、报错或无法证明实际写入时，不报告 flash success。flash 结果回显 exact artifact、guard JSON 摘要与 J-Link 结果；不得用 UART 日志替代 flash 结果验证。
