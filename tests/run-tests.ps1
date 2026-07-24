param([ValidateSet('all','discovery','image','contract')][string]$Case = 'all')

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

function Assert-NotContains([string]$Actual, [string]$Unexpected, [string]$Message) {
    if ($Actual.Contains($Unexpected)) { throw "$Message; unexpected '$Unexpected' in '$Actual'" }
}

function Invoke-Discovery([string]$FixtureName) {
    $fixture = Join-Path $PSScriptRoot "fixtures\$FixtureName"
    $json = & (Join-Path $RepoRoot 'scripts\discover-embedded.ps1') -ProjectRoot $fixture
    $json | ConvertFrom-Json
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

    $validLayout = Invoke-Discovery 'layout-valid'
    $validTarget = @($validLayout.projects.targets)[0]
    Assert-Equal $validTarget.layout_status 'consistent' 'Matching scatter and IROM must be consistent'
    Assert-Equal $validTarget.scatter_ranges.Count 1 'Expected one parsed scatter load region'
    Assert-Equal $validTarget.scatter_ranges[0].start '0x08004000' 'Scatter start mismatch'
    Assert-Equal $validTarget.scatter_ranges[0].end_exclusive '0x08040000' 'Scatter end mismatch'
    Assert-Equal $validTarget.effective_range.source 'scatter' 'Scatter must outrank IROM'
    Assert-Equal $validTarget.layout_conflicts.Count 0 'Matching layout must have no conflicts'

    $scatterConflict = Invoke-Discovery 'layout-scatter-conflict'
    $scatterConflictTarget = @($scatterConflict.projects.targets)[0]
    Assert-Equal $scatterConflictTarget.layout_status 'conflict' 'Scatter/IROM disagreement must conflict'
    Assert-Equal $scatterConflictTarget.role_hint 'unknown' 'Conflicting target must fail closed'
    Assert-Equal $scatterConflictTarget.effective_range $null 'Conflicting target must not expose an effective range'
    Assert-Contains (($scatterConflictTarget.layout_conflicts | ConvertTo-Json -Compress) -join '') 'scatter_vs_irom' 'Scatter/IROM conflict verdict missing'

    $configConflict = Invoke-Discovery 'layout-config-conflict'
    $configConflictTarget = @($configConflict.projects.targets)[0]
    Assert-Equal $configConflictTarget.layout_status 'conflict' 'Config/target disagreement must conflict'
    Assert-Equal $configConflictTarget.role_hint 'unknown' 'Config conflict must fail closed'
    Assert-Equal $configConflict.flash_layout_config.app.start '0x08008000' 'Config AppStart was not parsed'
    Assert-Contains (($configConflictTarget.layout_conflicts | ConvertTo-Json -Compress) -join '') 'config_vs_target' 'Config conflict verdict missing'

    $invalidScatter = Invoke-Discovery 'layout-invalid-scatter'
    $malformedScatter = @($invalidScatter.projects.targets) | Where-Object name -eq 'Application malformed scatter'
    Assert-Equal $malformedScatter.layout_status 'conflict' 'Malformed referenced scatter must fail closed'
    Assert-Equal $malformedScatter.role_hint 'unknown' 'Malformed scatter must clear role hint'
    Assert-Equal $malformedScatter.range_sources.scatter.status 'invalid' 'Malformed scatter status missing'
    $missingScatter = @($invalidScatter.projects.targets) | Where-Object name -eq 'Application missing scatter'
    Assert-Equal $missingScatter.layout_status 'conflict' 'Unreadable referenced scatter must fail closed'
    Assert-Equal $missingScatter.role_hint 'unknown' 'Unreadable scatter must clear role hint'
    Assert-Equal $missingScatter.range_sources.scatter.status 'unreadable' 'Unreadable scatter status missing'
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

function Invoke-ContractTests {
    $skill = Get-Content -LiteralPath (Join-Path $RepoRoot 'SKILL.md') -Raw -Encoding UTF8
    $reference = Get-Content -LiteralPath (Join-Path $RepoRoot 'references\embedlink-mcp.md') -Raw -Encoding UTF8
    $readme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw -Encoding UTF8
    $statusCheck = [regex]::Unescape('\u72b6\u6001\u68c0\u67e5')
    $mcpEndpoint = [regex]::Unescape('\u7aef\u70b9')

    Assert-Contains $skill 'Runtime order: inspect tool inventory first.' 'Tool inventory check must precede EmbedLink guidance'
    Assert-Contains $skill 'Tool available: no startup or new-session prompt.' 'Available Tool must not trigger restart guidance'
    Assert-Contains $skill '## EmbedLink' 'Unified config template must include EmbedLink section'
    Assert-Contains $skill "- ${statusCheck}: http://127.0.0.1:3000/health" 'EmbedLink health metadata missing'
    Assert-Contains $skill "- MCP${mcpEndpoint}: http://127.0.0.1:3000/mcp" 'EmbedLink MCP endpoint missing'

    Assert-Contains $reference 'Runtime: Claude Code; Tool: unavailable' 'Claude Code runtime branch missing'
    Assert-Contains $reference 'Action: start EmbedLink, create new Claude Code session, stop.' 'Claude Code missing Tool must require a new session'
    Assert-Contains $reference 'Runtime: Codex; Tool: unavailable' 'Codex runtime branch missing'
    Assert-Contains $reference 'recheck tool inventory once' 'Codex one-time inventory recheck missing'
    Assert-Contains $reference 'still unavailable: create a new Codex task' 'Codex must defer new-task guidance until recheck fails'
    Assert-Contains $reference 'Do not loop inventory checks.' 'Codex inventory recheck must not loop'
    Assert-Contains $reference 'URLs are configuration and manual troubleshooting metadata only.' 'EmbedLink URLs must be informational only'
    Assert-Contains $reference 'Agent must not request these HTTP endpoints directly.' 'Agent HTTP access must remain forbidden'

    Assert-Contains $readme '## EmbedLink' 'README config example must include EmbedLink section'
    Assert-Contains $readme 'Detect current EmbedLink MCP Tool before prompting.' 'README must explain detect-before-prompt behavior'
    Assert-NotContains $readme 'Always create a new Claude Code session.' 'README must not require unconditional Claude Code restart'
}

if ($Case -in @('all','discovery')) { Invoke-DiscoveryTests }
if ($Case -in @('all','image')) { Invoke-ImageTests }
if ($Case -in @('all','contract')) { Invoke-ContractTests }
if ($Case -eq 'contract') { 'Contract tests passed' }
if ($Case -eq 'all') { 'All tests passed' }
