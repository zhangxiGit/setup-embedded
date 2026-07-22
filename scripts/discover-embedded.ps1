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

function New-Range([UInt64]$Start, [UInt64]$Size, [string]$Name = $null) {
    if ($Size -eq 0 -or $Start -gt ([UInt64]::MaxValue - $Size)) { return $null }
    [pscustomobject][ordered]@{
        name = $Name
        start = Convert-ToHexString $Start
        end_exclusive = Convert-ToHexString ($Start + $Size)
        size = Convert-ToHexString $Size
    }
}

function Test-SameRange($Left, $Right) {
    $null -ne $Left -and $null -ne $Right -and
        $Left.start -eq $Right.start -and $Left.end_exclusive -eq $Right.end_exclusive
}

function Test-PathWithinRoot([string]$Path) {
    $rootPrefix = $resolvedProjectRoot.TrimEnd('\') + '\'
    $Path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Read-ScatterSource([string]$ProjectDirectory, [string]$ScatterValue) {
    $scatterPath = Resolve-OptionalPath $ProjectDirectory $ScatterValue
    if ($null -eq $scatterPath) {
        return [pscustomobject][ordered]@{ status = 'missing'; path = $null; ranges = @(); error = $null }
    }
    if (-not (Test-PathWithinRoot $scatterPath)) {
        return [pscustomobject][ordered]@{ status = 'invalid'; path = $scatterPath; ranges = @(); error = 'scatter file is outside workspace' }
    }
    if (-not (Test-Path -LiteralPath $scatterPath -PathType Leaf)) {
        return [pscustomobject][ordered]@{ status = 'unreadable'; path = $scatterPath; ranges = @(); error = 'referenced scatter file is not readable' }
    }

    try {
        $resolvedScatterPath = (Resolve-Path -LiteralPath $scatterPath).Path
        if (-not (Test-PathWithinRoot $resolvedScatterPath)) {
            return [pscustomobject][ordered]@{ status = 'invalid'; path = $resolvedScatterPath; ranges = @(); error = 'scatter file resolves outside workspace' }
        }
        $content = Get-Content -LiteralPath $resolvedScatterPath -Raw
    } catch {
        return [pscustomobject][ordered]@{ status = 'unreadable'; path = $scatterPath; ranges = @(); error = 'referenced scatter file is not readable' }
    }

    $ranges = @(
        foreach ($match in [regex]::Matches($content, '(?im)^\s*(LR_[A-Za-z0-9_]+)\s+(0[xX][0-9A-Fa-f]+|[0-9]+)\s+(0[xX][0-9A-Fa-f]+|[0-9]+)\s*\{')) {
            $start = Convert-ToUInt64OrNull $match.Groups[2].Value
            $size = Convert-ToUInt64OrNull $match.Groups[3].Value
            if ($null -eq $start -or $null -eq $size) { continue }
            $range = New-Range $start $size $match.Groups[1].Value
            if ($null -ne $range) { $range }
        }
    )
    if ($ranges.Count -eq 0) {
        return [pscustomobject][ordered]@{ status = 'invalid'; path = $resolvedScatterPath; ranges = @(); error = 'no valid Keil load region found' }
    }
    [pscustomobject][ordered]@{ status = 'valid'; path = $resolvedScatterPath; ranges = [object[]]$ranges; error = $null }
}

function Read-FlashLayoutConfig {
    $configPath = Join-Path $resolvedProjectRoot '.embedded\embedded-config.md'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return [pscustomobject][ordered]@{ status = 'missing'; path = $configPath; boot = $null; app = $null; error = $null }
    }
    try { $content = Get-Content -LiteralPath $configPath -Raw } catch {
        return [pscustomobject][ordered]@{ status = 'invalid'; path = $configPath; boot = $null; app = $null; error = 'unified config is not readable' }
    }
    $sectionMatch = [regex]::Match($content, '(?ims)^##\s+FlashLayout\s*$\s*(.*?)(?=^##\s+|\z)')
    if (-not $sectionMatch.Success) {
        return [pscustomobject][ordered]@{ status = 'invalid'; path = $configPath; boot = $null; app = $null; error = 'FlashLayout section is missing' }
    }
    $values = @{}
    foreach ($match in [regex]::Matches($sectionMatch.Groups[1].Value, '(?im)^\s*-\s*(BootStart|BootEndExclusive|AppStart|AppEndExclusive)\s*:\s*(\S+)\s*$')) {
        $values[$match.Groups[1].Value] = Convert-ToUInt64OrNull $match.Groups[2].Value
    }
    foreach ($key in @('BootStart','BootEndExclusive','AppStart','AppEndExclusive')) {
        if (-not $values.ContainsKey($key) -or $null -eq $values[$key]) {
            return [pscustomobject][ordered]@{ status = 'invalid'; path = $configPath; boot = $null; app = $null; error = "invalid or missing FlashLayout key: $key" }
        }
    }
    if ($values.BootEndExclusive -le $values.BootStart -or $values.AppEndExclusive -le $values.AppStart) {
        return [pscustomobject][ordered]@{ status = 'invalid'; path = $configPath; boot = $null; app = $null; error = 'FlashLayout range is empty or reversed' }
    }
    $boot = New-Range $values.BootStart ($values.BootEndExclusive - $values.BootStart)
    $app = New-Range $values.AppStart ($values.AppEndExclusive - $values.AppStart)
    [pscustomobject][ordered]@{ status = 'valid'; path = $configPath; boot = $boot; app = $app; error = $null }
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
$flashLayoutConfig = Read-FlashLayoutConfig
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
                $iromRange = if ($null -eq $start) { $null } else { New-Range $start $size }
                if ($null -eq $iromRange) { $start = $null; $size = $null }
                $scatterSource = Read-ScatterSource $projectDirectory ([string]$linkerOptions.ScatterFile)
                $candidateRole = Get-RoleHint ([string]$target.TargetName) $start
                $conflicts = @()
                if ($scatterSource.status -in @('invalid','unreadable')) {
                    $conflicts += [pscustomobject][ordered]@{ type = 'scatter_invalid'; sources = @('scatter'); message = $scatterSource.error }
                } elseif ($scatterSource.status -eq 'valid' -and $null -ne $iromRange) {
                    if ($scatterSource.ranges.Count -ne 1 -or -not (Test-SameRange $scatterSource.ranges[0] $iromRange)) {
                        $conflicts += [pscustomobject][ordered]@{ type = 'scatter_vs_irom'; sources = @('scatter','irom'); message = 'scatter load region does not match IROM range' }
                    }
                }

                $targetRange = if ($scatterSource.status -eq 'valid') {
                    if ($scatterSource.ranges.Count -eq 1) { $scatterSource.ranges[0] } else { $null }
                } else { $iromRange }
                $configSource = [pscustomobject][ordered]@{
                    status = $flashLayoutConfig.status
                    path = $flashLayoutConfig.path
                    role = if ($candidateRole -in @('boot','app')) { $candidateRole } else { $null }
                    boot = $flashLayoutConfig.boot
                    app = $flashLayoutConfig.app
                    start = $null
                    end_exclusive = $null
                    size = $null
                    error = $flashLayoutConfig.error
                }
                if ($flashLayoutConfig.status -eq 'valid' -and $null -ne $targetRange) {
                    $matchingConfigRole = @('boot','app') | Where-Object { Test-SameRange $flashLayoutConfig.$_ $targetRange }
                    if (@($matchingConfigRole).Count -eq 1) {
                        $candidateRole = [string]$matchingConfigRole
                        $configSource.role = $candidateRole
                    } elseif ($candidateRole -notin @('boot','app')) {
                        $conflicts += [pscustomobject][ordered]@{ type = 'config_vs_target'; sources = @('config','scatter','irom'); message = 'target range does not match any unified config range' }
                    }
                }
                if ($flashLayoutConfig.status -eq 'valid' -and $candidateRole -in @('boot','app')) {
                    $configRange = $flashLayoutConfig.$candidateRole
                    $configSource.start = $configRange.start
                    $configSource.end_exclusive = $configRange.end_exclusive
                    $configSource.size = $configRange.size
                    if ($null -ne $targetRange -and -not (Test-SameRange $configRange $targetRange)) {
                        $conflicts += [pscustomobject][ordered]@{ type = 'config_vs_target'; sources = @('config','scatter','irom'); message = 'unified config range does not match target range' }
                    }
                } elseif ($flashLayoutConfig.status -eq 'valid') {
                    $configSource.status = 'unassigned'
                } elseif ($flashLayoutConfig.status -eq 'invalid') {
                    $conflicts += [pscustomobject][ordered]@{ type = 'config_invalid'; sources = @('config'); message = $flashLayoutConfig.error }
                }

                $layoutStatus = if ($conflicts.Count -gt 0) { 'conflict' } elseif ($null -ne $targetRange) { 'consistent' } else { 'unknown' }
                $effectiveRange = $null
                if ($layoutStatus -eq 'consistent') {
                    if ($configSource.status -eq 'valid' -and $null -ne $configSource.start) {
                        $effectiveRange = [pscustomobject][ordered]@{ source = 'config'; start = $configSource.start; end_exclusive = $configSource.end_exclusive; size = $configSource.size }
                    } elseif ($scatterSource.status -eq 'valid' -and $scatterSource.ranges.Count -eq 1) {
                        $effectiveRange = [pscustomobject][ordered]@{ source = 'scatter'; start = $targetRange.start; end_exclusive = $targetRange.end_exclusive; size = $targetRange.size }
                    } elseif ($null -ne $iromRange) {
                        $effectiveRange = [pscustomobject][ordered]@{ source = 'irom'; start = $iromRange.start; end_exclusive = $iromRange.end_exclusive; size = $iromRange.size }
                    }
                }
                $outputName = [string]$commonOptions.OutputName
                $artifactPath = if ([string]::IsNullOrWhiteSpace($outputName)) {
                    $null
                } else {
                    Resolve-OptionalPath $projectDirectory (Join-Path ([string]$commonOptions.OutputDirectory) "$outputName.hex")
                }

                [pscustomobject][ordered]@{
                    name = [string]$target.TargetName
                    role_hint = if ($layoutStatus -eq 'conflict') { 'unknown' } else { $candidateRole }
                    irom_start = if ($null -eq $start) { $null } else { Convert-ToHexString $start }
                    irom_size = if ($null -eq $size) { $null } else { Convert-ToHexString $size }
                    scatter_file = $scatterSource.path
                    scatter_ranges = [object[]]$scatterSource.ranges
                    range_sources = [pscustomobject][ordered]@{
                        config = $configSource
                        scatter = $scatterSource
                        irom = [pscustomobject][ordered]@{
                            status = if ($null -eq $iromRange) { 'missing' } else { 'valid' }
                            start = if ($null -eq $iromRange) { $null } else { $iromRange.start }
                            end_exclusive = if ($null -eq $iromRange) { $null } else { $iromRange.end_exclusive }
                            size = if ($null -eq $iromRange) { $null } else { $iromRange.size }
                        }
                    }
                    layout_status = $layoutStatus
                    layout_conflicts = [object[]]$conflicts
                    effective_range = $effectiveRange
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
    flash_layout_config = $flashLayoutConfig
    projects = $projects
} | ConvertTo-Json -Depth 8
