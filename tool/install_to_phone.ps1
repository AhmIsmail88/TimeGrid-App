<#
.SYNOPSIS
    Installs dist\TimeGrid-01.apk on a USB-connected Android phone - safely.

.DESCRIPTION
    The phone already carries real work data in the app's private SQLite
    database, so this script is deliberately timid. It only ever runs
    `adb install -r`, which replaces the app in place while keeping its
    data, and it refuses to continue when that could cost the database:

      * no device is attached or authorised;
      * the copy already on the phone is signed with a different key, so
        Android would reject the update and the only way out would be an
        uninstall (which deletes the database).

    It prints the app's first-install timestamp before and after. As long
    as that value does not change, the install was an update and the
    on-device data was carried over.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\install_to_phone.ps1
#>
[CmdletBinding()]
param(
    [string]$Apk,
    [string]$PackageId = 'com.example.timegrid',
    [string]$Adb = 'D:\SDK\platform-tools\adb.exe',
    [string]$ApkSigner = 'D:\SDK\build-tools\36.0.0\apksigner.bat',
    [string]$JavaHome = 'C:\Program Files\Android\Android Studio\jbr'
)

# Native tools (adb, apksigner) print warnings on stderr, and PowerShell turns
# those into error records; with 'Stop' that would abort a run that is fine.
# Every step below therefore checks its own result explicitly.
$ErrorActionPreference = 'Continue'

# $PSScriptRoot is not always populated while parameters bind, so resolve the
# script's own folder here instead.
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $PSCommandPath }
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Apk) { $Apk = Join-Path $scriptDir '..\dist\TimeGrid-01.apk' }

function Fail($message) {
    Write-Host ''
    Write-Host "STOP: $message" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $Apk)) { Fail "APK not found: $Apk" }
$Apk = (Resolve-Path $Apk).Path
if (-not (Test-Path $Adb)) { Fail "adb not found: $Adb" }

# adb and apksigner both need a JVM on the path.
if (Test-Path $JavaHome) { $env:Path = "$JavaHome\bin;$env:Path" }

Write-Host "APK: $Apk"
Write-Host ("     {0:N2} MB" -f ((Get-Item $Apk).Length / 1MB))
Write-Host ''

# --- 1. exactly one authorised device -------------------------------------
$devices = & $Adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne '' }
$ready = @($devices | Where-Object { $_ -match '\sdevice$' })
$unauthorised = @($devices | Where-Object { $_ -match '\s(unauthorized|offline)$' })

if ($ready.Count -eq 0) {
    if ($unauthorised.Count -gt 0) {
        Fail "the phone is connected but not authorised. Unlock it, tap 'Allow' on the USB debugging prompt, then run this again."
    }
    Write-Host 'No phone is connected.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'On the phone:' -ForegroundColor Cyan
    Write-Host '  1. Settings -> About phone -> tap "Build number" 7 times to unlock Developer options.'
    Write-Host '  2. Settings -> Developer options -> turn on "USB debugging".'
    Write-Host '  3. Plug in the USB cable, choose "File transfer / MTP" if asked,'
    Write-Host '     then tap "Allow" on the "Allow USB debugging?" prompt.'
    Write-Host '  4. Run this script again.'
    exit 2
}
if ($ready.Count -gt 1) { Fail 'more than one device is connected; keep only the phone plugged in.' }

$serial = ($ready[0] -split '\s+')[0]
Write-Host "Device: $serial" -ForegroundColor Green
Write-Host ("        Android {0} (api {1}), {2}" -f `
        (& $Adb -s $serial shell getprop ro.build.version.release).Trim(), `
        (& $Adb -s $serial shell getprop ro.build.version.sdk).Trim(), `
        (& $Adb -s $serial shell getprop ro.product.cpu.abi).Trim())
Write-Host ''

# Prefer a build made for this device's ABI when one is next to the universal
# APK: it carries one set of native libraries instead of three, so it is about
# a third of the size and installs exactly the same way.
$deviceAbi = (& $Adb -s $serial shell getprop ro.product.cpu.abi).Trim()
$stem = [System.IO.Path]::GetFileNameWithoutExtension($Apk)
$folder = [System.IO.Path]::GetDirectoryName($Apk)
# Accept both the full ABI name (arm64-v8a) and its short form (arm64).
$shortAbi = $deviceAbi -replace '-.*$', ''
$slim = @(
    (Join-Path $folder "$stem-$deviceAbi.apk"),
    (Join-Path $folder "$stem-$shortAbi.apk")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($slim) {
    $universalMb = (Get-Item $Apk).Length / 1MB
    $Apk = $slim
    Write-Host ("Using the {0} build: {1:N2} MB instead of {2:N2} MB" -f `
        $deviceAbi, ((Get-Item $Apk).Length / 1MB), $universalMb) -ForegroundColor Cyan
    Write-Host ("  $Apk")
    Write-Host ''
}

function Get-SignerHash($path, $ApkSigner) {
    $out = & $ApkSigner verify --print-certs $path 2>&1 | Out-String
    return ([regex]::Match($out, 'certificate SHA-256 digest:\s*([0-9a-fA-F]+)')).Groups[1].Value.ToLower()
}

# --- 2. is it already installed? ------------------------------------------
$installed = (& $Adb -s $serial shell pm path $PackageId 2>$null | Out-String).Trim()
$firstInstallBefore = $null

if ($installed -match '^package:') {
    $dump = & $Adb -s $serial shell dumpsys package $PackageId | Out-String
    $firstInstallBefore = ([regex]::Match($dump, 'firstInstallTime=([^\r\n]+)')).Groups[1].Value.Trim()
    $versionCode = ([regex]::Match($dump, 'versionCode=(\d+)')).Groups[1].Value
    Write-Host "$PackageId is already installed (versionCode $versionCode)." -ForegroundColor Cyan
    Write-Host "  first installed: $firstInstallBefore"
    Write-Host '  This will be an in-place UPDATE; the app data is kept.'
    Write-Host ''

    # --- 3. signature compatibility ---------------------------------------
    $deviceApk = Join-Path $env:TEMP 'timegrid_installed.apk'
    $devicePath = ($installed -split '\r?\n')[0].Replace('package:', '').Trim()
    & $Adb -s $serial pull $devicePath $deviceApk | Out-Null

    $installedHash = Get-SignerHash $deviceApk $ApkSigner
    $newHash = Get-SignerHash $Apk $ApkSigner

    if ([string]::IsNullOrWhiteSpace($installedHash) -or [string]::IsNullOrWhiteSpace($newHash)) {
        Write-Host 'Could not read both signing certificates; continuing, but read the result carefully.' -ForegroundColor Yellow
    }
    elseif ($installedHash -ne $newHash) {
        Write-Host ''
        Write-Host 'STOP: SIGNATURE MISMATCH - the update would be rejected.' -ForegroundColor Red
        Write-Host "  installed app : $installedHash"
        Write-Host "  this APK      : $newHash"
        Write-Host ''
        Write-Host 'Android only accepts an update signed with the same key. Forcing this one'
        Write-Host 'through would mean uninstalling first, and that DELETES the on-device database.'
        Write-Host ''
        Write-Host 'First: open the installed app -> Settings -> Backup data, and copy that JSON'
        Write-Host 'file off the phone. Then decide together how to re-key the app.'
        exit 1
    }
    else {
        Write-Host "Signing key matches the installed app ($($newHash.Substring(0,16))...)." -ForegroundColor Green
        Write-Host ''
    }
}

# --- 4. install, keeping data ---------------------------------------------
Write-Host 'Installing (replace, keep data)...' -ForegroundColor Cyan
& $Adb -s $serial install -r $Apk
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host "STOP: adb install returned $LASTEXITCODE." -ForegroundColor Red
    Write-Host 'Do NOT uninstall the app. Send this output back instead.' -ForegroundColor Red
    exit 1
}

# --- 5. prove the data was preserved --------------------------------------
Start-Sleep -Seconds 2
$dumpAfter = & $Adb -s $serial shell dumpsys package $PackageId | Out-String
$firstInstallAfter = ([regex]::Match($dumpAfter, 'firstInstallTime=([^\r\n]+)')).Groups[1].Value.Trim()
$lastUpdate = ([regex]::Match($dumpAfter, 'lastUpdateTime=([^\r\n]+)')).Groups[1].Value.Trim()
$versionCodeAfter = ([regex]::Match($dumpAfter, 'versionCode=(\d+)')).Groups[1].Value

Write-Host ''
if (-not $firstInstallBefore) {
    Write-Host 'Installed as a NEW app: this package was not on the phone before,' -ForegroundColor Green
    Write-Host 'so nothing of yours was touched or replaced.'
}
elseif ($firstInstallAfter -ne $firstInstallBefore) {
    Write-Host 'WARNING: firstInstallTime changed, so this looks like a fresh install rather than an update.' -ForegroundColor Yellow
    Write-Host '         Do not uninstall anything: open the app and check for your data first.' -ForegroundColor Yellow
}
else {
    Write-Host 'OK: firstInstallTime is unchanged - the update kept the app data.' -ForegroundColor Green
}
Write-Host "  versionCode     : $versionCodeAfter"
Write-Host "  lastUpdateTime  : $lastUpdate"
Write-Host ''
Write-Host 'Next: open TimeGrid on the phone and confirm your projects, tasks and' -ForegroundColor Cyan
Write-Host 'logged hours are all still there.'
