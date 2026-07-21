param([ValidateSet('all','discovery','image')][string]$Case = 'all')

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message`nExpected: $Expected`nActual: $Actual" }
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

if ($Case -in @('all','discovery')) { Invoke-DiscoveryTests }
