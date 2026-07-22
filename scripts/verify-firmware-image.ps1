$ErrorActionPreference = 'Stop'

function Convert-ToUInt64([string]$Value) {
    if ($Value -match '^0x([0-9a-fA-F]+)$') { return [Convert]::ToUInt64($Matches[1], 16) }
    if ($Value -notmatch '^[0-9]+$') { throw "Invalid unsigned integer: $Value" }
    return [Convert]::ToUInt64($Value, 10)
}

function Test-Overlap([UInt64]$AStart, [UInt64]$AEnd, [UInt64]$BStart, [UInt64]$BEnd) {
    ($AStart -lt $BEnd) -and ($BStart -lt $AEnd)
}

function Stop-Unsafe([string]$Message) {
    $json = [ordered]@{ safe = $false; error = $Message } | ConvertTo-Json -Compress
    [Console]::Error.WriteLine($json)
    exit 2
}

function Get-HexRanges([string]$Path) {
    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines.Count -eq 0) { throw 'HEX image is empty' }

    [UInt64]$baseAddress = 0
    $endRecordSeen = $false
    $ranges = @()
    foreach ($line in $lines) {
        if ($endRecordSeen) { throw 'HEX data follows end-of-file record' }
        if ($line -notmatch '^:([0-9A-Fa-f]+)$') { throw 'Malformed HEX record prefix or characters' }

        $hex = $Matches[1]
        if (($hex.Length % 2) -ne 0 -or $hex.Length -lt 10) { throw 'Malformed HEX record length' }
        [int]$byteCount = [Convert]::ToInt32($hex.Substring(0, 2), 16)
        if (($hex.Length / 2) -ne ($byteCount + 5)) { throw 'HEX byte count does not match record length' }

        $bytes = @()
        for ($index = 0; $index -lt $hex.Length; $index += 2) {
            $bytes += [Convert]::ToByte($hex.Substring($index, 2), 16)
        }
        [int]$checksum = 0
        foreach ($byte in $bytes) { $checksum = ($checksum + $byte) -band 0xFF }
        if ($checksum -ne 0) { throw 'HEX checksum is invalid' }

        [UInt64]$address = [Convert]::ToUInt16($hex.Substring(2, 4), 16)
        [int]$recordType = $bytes[3]
        $data = if ($byteCount -eq 0) { @() } else { @($bytes[4..(3 + $byteCount)]) }
        switch ($recordType) {
            0 {
                if ($byteCount -eq 0) { break }
                [UInt64]$start = $baseAddress + $address
                [UInt64]$end = $start + [UInt64]$byteCount
                if ($end -lt $start) { throw 'HEX data range overflows address space' }
                $ranges += [pscustomobject]@{ start = $start; end = $end }
            }
            1 {
                if ($byteCount -ne 0 -or $address -ne 0) { throw 'Malformed HEX end-of-file record' }
                $endRecordSeen = $true
            }
            2 {
                if ($byteCount -ne 2 -or $address -ne 0) { throw 'Malformed HEX extended segment record' }
                $baseAddress = [UInt64]((([UInt16]$data[0] -shl 8) -bor [UInt16]$data[1])) -shl 4
            }
            4 {
                if ($byteCount -ne 2 -or $address -ne 0) { throw 'Malformed HEX extended linear record' }
                $baseAddress = [UInt64]((([UInt16]$data[0] -shl 8) -bor [UInt16]$data[1])) -shl 16
            }
        }
    }

    if (-not $endRecordSeen) { throw 'HEX image is missing end-of-file record' }
    return $ranges
}

function Merge-Ranges($Ranges) {
    $merged = @()
    foreach ($range in @($Ranges | Sort-Object start, end)) {
        if ($merged.Count -eq 0) {
            $merged += [pscustomobject]@{ start = [UInt64]$range.start; end = [UInt64]$range.end }
            continue
        }
        $last = $merged[$merged.Count - 1]
        if ($range.start -le $last.end) {
            if ($range.end -gt $last.end) { $last.end = [UInt64]$range.end }
            continue
        }
        $merged += [pscustomobject]@{ start = [UInt64]$range.start; end = [UInt64]$range.end }
    }
    return $merged
}

try {
    $rawArguments = @($args)
    $valueParameterNames = @('ImagePath', 'Mode', 'BootStart', 'BootEndExclusive', 'AppStart', 'AppEndExclusive', 'LoadAddress')
    $switchParameterNames = @('AppStartEraseBoundaryConfirmed', 'BootFlashConfirmed')
    $parsedArguments = @{}
    $seenParameters = @{}

    for ($index = 0; $index -lt $rawArguments.Count; $index++) {
        $token = [string]$rawArguments[$index]
        if (-not $token.StartsWith('-') -or $token.Length -eq 1) { Stop-Unsafe "Unexpected positional argument: $token" }

        $parameterToken = $token.Substring(1)
        $nameAndValue = @($parameterToken -split ':', 2)
        $name = $nameAndValue[0]
        $hasAttachedValue = $nameAndValue.Count -eq 2
        $attachedValue = if ($hasAttachedValue) { $nameAndValue[1] } else { $null }

        if ($valueParameterNames -contains $name) {
            if ($seenParameters.ContainsKey($name)) { Stop-Unsafe "Duplicate parameter: $name" }
            if ($hasAttachedValue) {
                $value = $attachedValue
            } else {
                if ($index + 1 -ge $rawArguments.Count -or ([string]$rawArguments[$index + 1]).StartsWith('-')) {
                    Stop-Unsafe "Missing value for parameter: $name"
                }
                $index++
                $value = [string]$rawArguments[$index]
            }
            if ([string]::IsNullOrWhiteSpace($value)) { Stop-Unsafe "Missing value for parameter: $name" }
            $seenParameters[$name] = $true
            $parsedArguments[$name] = $value
            continue
        }

        if ($switchParameterNames -contains $name) {
            if ($seenParameters.ContainsKey($name)) { Stop-Unsafe "Duplicate parameter: $name" }
            if (-not $hasAttachedValue) {
                $switchValue = $true
            } elseif ($attachedValue -in @('$true', 'true', '1')) {
                $switchValue = $true
            } elseif ($attachedValue -in @('$false', 'false', '0')) {
                $switchValue = $false
            } else {
                Stop-Unsafe "Invalid switch syntax: $name"
            }
            $seenParameters[$name] = $true
            $parsedArguments[$name] = $switchValue
            continue
        }

        Stop-Unsafe "Unknown argument: $token"
    }

    $ImagePath = $parsedArguments['ImagePath']
    $Mode = $parsedArguments['Mode']
    $BootStart = $parsedArguments['BootStart']
    $BootEndExclusive = $parsedArguments['BootEndExclusive']
    $AppStart = $parsedArguments['AppStart']
    $AppEndExclusive = $parsedArguments['AppEndExclusive']
    $LoadAddress = $parsedArguments['LoadAddress']
    $AppStartEraseBoundaryConfirmed = $parsedArguments.ContainsKey('AppStartEraseBoundaryConfirmed') -and $parsedArguments['AppStartEraseBoundaryConfirmed']
    $BootFlashConfirmed = $parsedArguments.ContainsKey('BootFlashConfirmed') -and $parsedArguments['BootFlashConfirmed']

    foreach ($requiredParameter in @(
        @{ Name = 'ImagePath'; Value = $ImagePath },
        @{ Name = 'Mode'; Value = $Mode },
        @{ Name = 'BootStart'; Value = $BootStart },
        @{ Name = 'BootEndExclusive'; Value = $BootEndExclusive },
        @{ Name = 'AppStart'; Value = $AppStart },
        @{ Name = 'AppEndExclusive'; Value = $AppEndExclusive }
    )) {
        if ([string]::IsNullOrWhiteSpace($requiredParameter.Value)) { Stop-Unsafe "Missing required parameter: $($requiredParameter.Name)" }
    }
    if ($Mode -notin @('app', 'boot')) { Stop-Unsafe "Invalid mode: $Mode" }

    $imageItem = Get-Item -LiteralPath $ImagePath -ErrorAction Stop
    if ($imageItem.PSIsContainer) { Stop-Unsafe 'Firmware image path must be a file' }
    $resolvedImagePath = $imageItem.FullName
    [UInt64]$imageLength = $imageItem.Length
    if ($imageLength -eq 0) { Stop-Unsafe 'Firmware image is empty' }

    [UInt64]$bootStartValue = Convert-ToUInt64 $BootStart
    [UInt64]$bootEndValue = Convert-ToUInt64 $BootEndExclusive
    [UInt64]$appStartValue = Convert-ToUInt64 $AppStart
    [UInt64]$appEndValue = Convert-ToUInt64 $AppEndExclusive
    if ($bootStartValue -ge $bootEndValue -or $appStartValue -ge $appEndValue) { Stop-Unsafe 'Firmware ranges are invalid' }
    if (Test-Overlap $bootStartValue $bootEndValue $appStartValue $appEndValue) { Stop-Unsafe 'Boot and application ranges overlap' }

    $extension = [IO.Path]::GetExtension($resolvedImagePath).ToLowerInvariant()
    if ($extension -eq '.hex') {
        $ranges = Merge-Ranges (Get-HexRanges $resolvedImagePath)
    } elseif ($extension -eq '.bin') {
        if ([string]::IsNullOrWhiteSpace($LoadAddress)) { Stop-Unsafe 'BIN image requires LoadAddress' }
        [UInt64]$start = Convert-ToUInt64 $LoadAddress
        if ([UInt64]::MaxValue - $start -lt $imageLength) { Stop-Unsafe 'BIN image range overflows address space' }
        $ranges = @([pscustomobject]@{ start = $start; end = $start + $imageLength })
    } else {
        Stop-Unsafe "Unsupported firmware image format: $extension"
    }

    if ($ranges.Count -eq 0) { Stop-Unsafe 'Firmware image contains no data records' }
    if ($Mode -eq 'app') {
        if (-not $AppStartEraseBoundaryConfirmed) { Stop-Unsafe 'Application start erase boundary is not confirmed' }
        foreach ($range in $ranges) {
            if (Test-Overlap $range.start $range.end $bootStartValue $bootEndValue) { Stop-Unsafe 'Application image overlaps boot range' }
            if ($range.start -lt $appStartValue -or $range.end -gt $appEndValue) { Stop-Unsafe 'Application image escapes application range' }
        }
    } else {
        if (-not $BootFlashConfirmed) { Stop-Unsafe 'Boot flash is not confirmed' }
        foreach ($range in $ranges) {
            if ($range.start -lt $bootStartValue -or $range.end -gt $bootEndValue) { Stop-Unsafe 'Boot image escapes boot range' }
        }
    }

    [ordered]@{
        safe = $true
        mode = $Mode
        image_path = $resolvedImagePath
        ranges = @($ranges | ForEach-Object {
            [ordered]@{ start = ('0x{0:X8}' -f $_.start); end_exclusive = ('0x{0:X8}' -f $_.end) }
        })
    } | ConvertTo-Json -Depth 5
} catch {
    Stop-Unsafe $_.Exception.Message
}
