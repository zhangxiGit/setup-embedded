param([ValidateSet('all','discovery','image')][string]$Case = 'all')

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message`nExpected: $Expected`nActual: $Actual" }
}

function Assert-Exit([int]$Actual, [int]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message; expected $Expected, got $Actual" }
}

function Assert-Contains([string]$Actual, [string]$Expected, [string]$Message) {
    if (-not $Actual.Contains($Expected)) { throw "$Message; missing '$Expected' in '$Actual'" }
}

function Invoke-Guard(
    [string]$Image,
    [string]$Mode = 'app',
    [switch]$Boundary,
    [switch]$BootConfirmed,
    [string]$LoadAddress
) {
    $script = Join-Path $RepoRoot 'scripts\verify-firmware-image.ps1'
    $guardArgs = @('-ImagePath', $Image, '-Mode', $Mode, '-BootStart', '0x08000000',
        '-BootEndExclusive', '0x08004000', '-AppStart', '0x08004000',
        '-AppEndExclusive', '0x08040000')
    if ($Boundary) { $guardArgs += '-AppStartEraseBoundaryConfirmed' }
    if ($BootConfirmed) { $guardArgs += '-BootFlashConfirmed' }
    if ($LoadAddress) { $guardArgs += @('-LoadAddress', $LoadAddress) }
    return Invoke-GuardCommand $guardArgs
}

function Invoke-GuardCommand([string[]]$GuardArgs) {
    $script = Join-Path $RepoRoot 'scripts\verify-firmware-image.ps1'
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script @GuardArgs 2>&1
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Invoke-DiscoveryTests {
    $fixture = Join-Path $PSScriptRoot 'fixtures\dual-project'
    $json = & (Join-Path $RepoRoot 'scripts\discover-embedded.ps1') -ProjectRoot $fixture
    $result = $json | ConvertFrom-Json
    Assert-Equal $result.schema_version 1 'schema_version mismatch'
    Assert-Equal $result.projects.Count 2 'Expected boot and app projects'
    $targets = @($result.projects.targets)
    Assert-Equal (@($targets | Where-Object role_hint -eq 'boot').Count) 1 'Expected one boot hint'
    Assert-Equal (@($targets | Where-Object role_hint -eq 'app').Count) 1 'Expected one app hint'
    Assert-Equal (@($targets | Where-Object artifact_path -like '*app.hex').Count) 1 'App artifact missing'

    $invalidFixture = Join-Path $PSScriptRoot 'fixtures\invalid-irom'
    $invalidJson = & (Join-Path $RepoRoot 'scripts\discover-embedded.ps1') -ProjectRoot $invalidFixture
    $invalidResult = $invalidJson | ConvertFrom-Json
    $invalidTargets = @($invalidResult.projects.targets)
    $missingIrom = $invalidTargets | Where-Object name -eq 'Bootloader without IROM'
    Assert-Equal $missingIrom.irom_start $null 'Missing IROM start must be null'
    Assert-Equal $missingIrom.irom_size $null 'Missing IROM size must be null'
    Assert-Equal $missingIrom.role_hint 'unknown' 'Missing IROM must not infer boot role'
    $uppercaseIrom = $invalidTargets | Where-Object name -eq 'Uppercase IROM prefix'
    Assert-Equal $uppercaseIrom.irom_start $null 'Invalid IROM size must clear start address'
    Assert-Equal $uppercaseIrom.irom_size $null 'Malformed IROM size must be null'
    Assert-Equal $uppercaseIrom.role_hint 'unknown' 'Invalid IROM size must not infer a role'
    $malformedSizeIrom = $invalidTargets | Where-Object name -eq 'Application with malformed IROM size'
    Assert-Equal $malformedSizeIrom.irom_start $null 'Application with malformed size must clear start address'
    Assert-Equal $malformedSizeIrom.irom_size $null 'Application malformed IROM size must be null'
    Assert-Equal $malformedSizeIrom.role_hint 'unknown' 'Application with malformed size must not infer app role'
    $malformedIrom = $invalidTargets | Where-Object name -eq 'Application with malformed IROM'
    Assert-Equal $malformedIrom.irom_start $null 'Malformed IROM start must be null'
    Assert-Equal $malformedIrom.irom_size $null 'Malformed IROM size must be null'
    Assert-Equal $malformedIrom.role_hint 'unknown' 'Malformed IROM must not infer app role'
}

function Invoke-ImageTests {
    $images = Join-Path $PSScriptRoot 'fixtures\images'
    $guardRanges = @('-BootStart', '0x08000000', '-BootEndExclusive', '0x08004000',
        '-AppStart', '0x08004000', '-AppEndExclusive', '0x08040000')
    $safeGuardArgs = @('-ImagePath', (Join-Path $images 'app-safe.hex'), '-Mode', 'app') + $guardRanges + '-AppStartEraseBoundaryConfirmed'
    Assert-Exit (Invoke-GuardCommand $safeGuardArgs).ExitCode 0 'Valid safe invocation rejected'
    Assert-Exit (Invoke-GuardCommand ($safeGuardArgs + '-Bogus')).ExitCode 2 'Unknown named argument accepted'
    Assert-Exit (Invoke-GuardCommand ($safeGuardArgs + 'trailing-token')).ExitCode 2 'Trailing positional argument accepted'
    $missingImageValue = Invoke-GuardCommand (@('-ImagePath', '-Mode', 'app') + $guardRanges + '-AppStartEraseBoundaryConfirmed')
    Assert-Exit $missingImageValue.ExitCode 2 'Missing parameter value did not exit 2'
    $missingImageJson = $missingImageValue.Output | ConvertFrom-Json
    Assert-Equal $missingImageJson.safe $false 'Missing parameter value must return unsafe JSON'
    Assert-Contains $missingImageJson.error 'ImagePath' 'Missing parameter value must identify ImagePath'
    $invalidSwitch = Invoke-GuardCommand ($safeGuardArgs[0..($safeGuardArgs.Count - 2)] + '-AppStartEraseBoundaryConfirmed:notbool')
    Assert-Exit $invalidSwitch.ExitCode 2 'Invalid switch syntax did not exit 2'
    $invalidSwitchJson = $invalidSwitch.Output | ConvertFrom-Json
    Assert-Equal $invalidSwitchJson.safe $false 'Invalid switch syntax must return unsafe JSON'
    Assert-Equal ([string]::IsNullOrWhiteSpace($invalidSwitchJson.error)) $false 'Invalid switch syntax must return an error message'
    $duplicateMode = Invoke-GuardCommand ($safeGuardArgs + @('-Mode', 'app'))
    Assert-Exit $duplicateMode.ExitCode 2 'Duplicate parameter did not exit 2'
    $duplicateModeJson = $duplicateMode.Output | ConvertFrom-Json
    Assert-Equal $duplicateModeJson.safe $false 'Duplicate parameter must return unsafe JSON'
    Assert-Contains $duplicateModeJson.error 'Mode' 'Duplicate parameter must identify Mode'
    $safeApp = Invoke-Guard (Join-Path $images 'app-safe.hex') -Boundary
    Assert-Exit $safeApp.ExitCode 0 'Safe app HEX rejected'
    $safeJson = $safeApp.Output | ConvertFrom-Json
    Assert-Equal $safeJson.safe $true 'Safe output must set safe'
    Assert-Equal $safeJson.mode 'app' 'Safe output mode mismatch'
    Assert-Equal $safeJson.image_path (Resolve-Path -LiteralPath (Join-Path $images 'app-safe.hex')).Path 'Safe output image path mismatch'
    Assert-Equal $safeJson.ranges.Count 1 'Safe output range count mismatch'
    Assert-Equal $safeJson.ranges[0].start '0x08004000' 'Safe output range start mismatch'
    Assert-Equal $safeJson.ranges[0].end_exclusive '0x08004004' 'Safe output range end mismatch'

    Assert-Exit (Invoke-Guard (Join-Path $images 'app-overlaps-boot.hex') -Boundary).ExitCode 2 'Boot overlap accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'app-out-of-range.hex') -Boundary).ExitCode 2 'Out-of-range image accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'bad-checksum.hex') -Boundary).ExitCode 2 'Bad checksum accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'empty.hex') -Boundary).ExitCode 2 'Empty image accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'app-safe.hex')).ExitCode 2 'Missing erase-boundary confirmation accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'app-overlaps-boot.hex') 'boot').ExitCode 2 'Unconfirmed boot flash accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'app-safe.hex') 'boot' -BootConfirmed).ExitCode 2 'App range accepted in boot mode'
    Assert-Exit (Invoke-Guard (Join-Path $images 'app-overlaps-boot.hex') 'boot' -BootConfirmed).ExitCode 0 'Confirmed boot HEX rejected'

    $binWithoutAddress = Invoke-Guard (Join-Path $images 'app-safe.bin') -Boundary
    Assert-Exit $binWithoutAddress.ExitCode 2 'BIN without load address accepted'
    Assert-Contains $binWithoutAddress.Output 'LoadAddress' 'BIN rejection must identify missing load address'
    Assert-Exit (Invoke-Guard (Join-Path $images 'app-safe.bin') -Boundary -LoadAddress '0x08004000').ExitCode 0 'BIN with valid load address rejected'
    $binDirectory = Join-Path $images 'directory.bin'
    $directoryResult = Invoke-Guard $binDirectory -Boundary -LoadAddress '0x08004000'
    Assert-Exit $directoryResult.ExitCode 2 'Directory named .bin accepted'
    Assert-Contains $directoryResult.Output 'must be a file' 'Directory rejection must identify non-file image'
    Assert-Exit (Invoke-Guard (Join-Path $images 'app-safe.bin') -Boundary -LoadAddress '0xFFFFFFFFFFFFFFFF').ExitCode 2 'Overflowing BIN address accepted'

    Assert-Exit (Invoke-GuardCommand @('-Mode', 'app') + $guardRanges).ExitCode 2 'Missing image path did not exit 2'
    Assert-Exit (Invoke-GuardCommand @('-ImagePath', (Join-Path $images 'app-safe.hex'), '-Mode', 'invalid') + $guardRanges).ExitCode 2 'Invalid mode did not exit 2'
    Assert-Exit (Invoke-GuardCommand @('-ImagePath', (Join-Path $images 'app-safe.hex'), '-Mode', 'app', '-BootEndExclusive', '0x08004000', '-AppStart', '0x08004000', '-AppEndExclusive', '0x08040000')).ExitCode 2 'Missing boot range did not exit 2'
    Assert-Exit (Invoke-GuardCommand @('-ImagePath', (Join-Path $images 'app-safe.hex'), '-Mode', 'app', '-BootStart', 'not-a-number',
        '-BootEndExclusive', '0x08004000', '-AppStart', '0x08004000', '-AppEndExclusive', '0x08040000', '-AppStartEraseBoundaryConfirmed')).ExitCode 2 'Invalid UInt64 input accepted'

    Assert-Exit (Invoke-Guard (Join-Path $images 'malformed-prefix.hex') -Boundary).ExitCode 2 'Malformed HEX prefix accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'bad-count.hex') -Boundary).ExitCode 2 'Malformed HEX byte count accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'bad-record-length.hex') -Boundary).ExitCode 2 'Malformed HEX record length accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'missing-eof.hex') -Boundary).ExitCode 2 'HEX without EOF accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'data-after-eof.hex') -Boundary).ExitCode 2 'HEX data after EOF accepted'
    Assert-Exit (Invoke-Guard (Join-Path $images 'eof-only.hex') -Boundary).ExitCode 2 'EOF-only HEX accepted'

    $unknownRecord = Invoke-Guard (Join-Path $images 'unknown-record.hex') -Boundary
    Assert-Exit $unknownRecord.ExitCode 0 'Checksum-valid unknown HEX record rejected'
    $mergedRanges = Invoke-Guard (Join-Path $images 'merged-ranges.hex') -Boundary
    Assert-Exit $mergedRanges.ExitCode 0 'Adjacent or overlapping HEX ranges rejected'
    $mergedJson = $mergedRanges.Output | ConvertFrom-Json
    Assert-Equal $mergedJson.ranges.Count 1 'Adjacent or overlapping ranges were not merged'
    Assert-Equal $mergedJson.ranges[0].start '0x08004000' 'Merged range start mismatch'
    Assert-Equal $mergedJson.ranges[0].end_exclusive '0x0800400A' 'Merged range end mismatch'
    $segmentResult = Invoke-GuardCommand @('-ImagePath', (Join-Path $images 'type-02-safe.hex'), '-Mode', 'app',
        '-BootStart', '0x00000000', '-BootEndExclusive', '0x00004000', '-AppStart', '0x00080000',
        '-AppEndExclusive', '0x00090000', '-AppStartEraseBoundaryConfirmed')
    Assert-Exit $segmentResult.ExitCode 0 'Type 02 HEX record rejected'
    $segmentJson = $segmentResult.Output | ConvertFrom-Json
    Assert-Equal $segmentJson.ranges[0].start '0x00084000' 'Type 02 range start mismatch'
}

if ($Case -in @('all','discovery')) { Invoke-DiscoveryTests }
if ($Case -in @('all','image')) { Invoke-ImageTests }
if ($Case -eq 'all') { 'All tests passed' }
