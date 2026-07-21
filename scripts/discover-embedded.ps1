[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [string]$UV4Path,
    [string]$JLinkPath
)

$ErrorActionPreference = 'Stop'

function Convert-ToHexString([UInt64]$Value) { '0x{0:X8}' -f $Value }

function Resolve-OptionalPath([string]$Base, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $candidate = if ([IO.Path]::IsPathRooted($Value)) { $Value } else { Join-Path $Base $Value }
    [IO.Path]::GetFullPath($candidate)
}

function Get-RoleHint([string]$Name, [Nullable[UInt64]]$Start) {
    if ($null -eq $Start) { return 'unknown' }
    if ($Name -match '(?i)boot|loader') { return 'boot' }
    if ($Name -match '(?i)app|application') { return 'app' }
    if ($Start -eq 0x08000000) { return 'boot' }
    'unknown'
}

function Convert-ToUInt64OrNull([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $trimmedValue = $Value.Trim()
    try {
        if ($trimmedValue -match '^(?i)0x') { return [Convert]::ToUInt64($trimmedValue.Substring(2), 16) }
        [Convert]::ToUInt64($trimmedValue, 10)
    } catch {
        $null
    }
}

function Find-ToolPath([string]$ExplicitPath, [string]$CommandName, [string[]]$KnownPaths) {
    $resolvedExplicitPath = Resolve-OptionalPath $resolvedProjectRoot $ExplicitPath
    if ($null -ne $resolvedExplicitPath) { return $resolvedExplicitPath }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    foreach ($path in $KnownPaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
    $null
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$projects = @(
    foreach ($projectFile in Get-ChildItem -LiteralPath $resolvedProjectRoot -Recurse -Filter '*.uvprojx' -File) {
        [xml]$projectXml = Get-Content -LiteralPath $projectFile.FullName -Raw
        $projectDirectory = Split-Path -Parent $projectFile.FullName
        $targets = @(
            foreach ($target in @($projectXml.Project.Targets.Target)) {
                $options = $target.TargetOption
                $commonOptions = $options.TargetCommonOption
                $linkerOptions = $options.TargetArmAds.LDads
                $start = Convert-ToUInt64OrNull $linkerOptions.IROM.StartAddress
                $size = Convert-ToUInt64OrNull $linkerOptions.IROM.Size
                if ($null -eq $start -or $null -eq $size) {
                    $start = $null
                    $size = $null
                }
                $outputName = [string]$commonOptions.OutputName
                $artifactPath = if ([string]::IsNullOrWhiteSpace($outputName)) {
                    $null
                } else {
                    Resolve-OptionalPath $projectDirectory (Join-Path ([string]$commonOptions.OutputDirectory) "$outputName.hex")
                }

                [pscustomobject][ordered]@{
                    name = [string]$target.TargetName
                    role_hint = Get-RoleHint ([string]$target.TargetName) $start
                    irom_start = if ($null -eq $start) { $null } else { Convert-ToHexString $start }
                    irom_size = if ($null -eq $size) { $null } else { Convert-ToHexString $size }
                    scatter_file = Resolve-OptionalPath $projectDirectory ([string]$linkerOptions.ScatterFile)
                    artifact_path = $artifactPath
                }
            }
        )
        [pscustomobject][ordered]@{
            path = $projectFile.FullName
            targets = $targets
        }
    }
)

[pscustomobject][ordered]@{
    schema_version = 1
    tools = [pscustomobject][ordered]@{
        uv4_path = Find-ToolPath $UV4Path 'UV4.exe' @('C:\Keil_v5\UV4\UV4.exe', 'C:\Keil\UV4\UV4.exe')
        jlink_path = Find-ToolPath $JLinkPath 'JLink.exe' @('C:\Program Files\SEGGER\JLink\JLink.exe')
    }
    projects = $projects
} | ConvertTo-Json -Depth 8
