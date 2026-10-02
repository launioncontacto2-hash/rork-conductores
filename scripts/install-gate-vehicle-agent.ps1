param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('DMP-002','DMP-003')]
  [string]$VehicleCode
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$gateRoot = Split-Path $repoRoot -Parent
$adb = Join-Path $gateRoot 'tools\platform-tools\adb.exe'
$artifactRoot = Join-Path $gateRoot 'artifacts\vehicle-agent\c778712'
$apk = Join-Path $artifactRoot "$VehicleCode\dori-vehicle-agent-$VehicleCode-live-v0.8.apk"

if (!(Test-Path $adb)) { throw "ADB_NOT_FOUND: $adb" }
if (!(Test-Path $apk)) { throw "APK_NOT_FOUND: $apk" }

$deviceLines = & $adb devices -l | Where-Object { $_ -match '^\S+\s+device(?:\s|$)' }
if ($deviceLines.Count -ne 1) {
  throw "EXPECTED_EXACTLY_ONE_ADB_DEVICE: found $($deviceLines.Count)"
}
$serial = ($deviceLines[0] -split '\s+')[0]
Write-Output "TARGET=$VehicleCode SERIAL=$serial"
& $adb -s $serial install -r $apk
if ($LASTEXITCODE -ne 0) { throw 'ADB_INSTALL_FAILED' }

$packagePath = & $adb -s $serial shell pm path mx.dori.vehicleagent.probe
if ($LASTEXITCODE -ne 0 -or -not ($packagePath -match '^package:')) {
  throw 'PACKAGE_VERIFY_FAILED'
}

& $adb -s $serial shell am start -n mx.dori.vehicleagent.probe/.MainActivity
if ($LASTEXITCODE -ne 0) { throw 'APP_LAUNCH_FAILED' }

Write-Output "VEHICLE_AGENT_INSTALL=PASS VEHICLE=$VehicleCode SERIAL=$serial"
