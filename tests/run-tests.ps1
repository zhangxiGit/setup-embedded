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
}

if ($Case -in @('all','discovery')) { Invoke-DiscoveryTests }
