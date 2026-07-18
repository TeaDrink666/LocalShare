[CmdletBinding()]
param(
    [switch]$SyncGradleInitOnly
)

$ErrorActionPreference = 'Stop'

$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$toolRoot = Join-Path $workspace 'LocalShare'
$flutter = Join-Path $toolRoot 'flutter-3.24.5\bin\flutter.bat'
$androidSdk = Join-Path $toolRoot 'android-sdk'
$gradleHome = Join-Path $toolRoot 'gradle-home'
$gradleInitTemplate = Join-Path $PSScriptRoot 'localshare_mirrors.init.gradle'
$gradleInit = Join-Path $gradleHome 'init.gradle'
$javaHome = 'D:\software_D\Java\jdk-17.0.18.8-hotspot'

foreach ($requiredPath in @($flutter, $androidSdk, $javaHome, $gradleInitTemplate)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required LocalShare build dependency is missing: $requiredPath"
    }
}

if (Test-Path -LiteralPath $gradleHome -PathType Leaf) {
    throw "The dedicated LocalShare Gradle home is a file, not a directory: $gradleHome"
}
if (-not (Test-Path -LiteralPath $gradleHome -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $gradleHome)
}

$expectedInitHash = (Get-FileHash -LiteralPath $gradleInitTemplate -Algorithm SHA256).Hash
$currentInitHash = if (Test-Path -LiteralPath $gradleInit -PathType Leaf) {
    (Get-FileHash -LiteralPath $gradleInit -Algorithm SHA256).Hash
} else {
    $null
}

if ($currentInitHash -ne $expectedInitHash) {
    $temporaryInit = Join-Path $gradleHome ("init.gradle.localshare.{0}.tmp" -f [Guid]::NewGuid().ToString('N'))
    $backupInit = "$temporaryInit.bak"
    try {
        Copy-Item -LiteralPath $gradleInitTemplate -Destination $temporaryInit
        if (Test-Path -LiteralPath $gradleInit -PathType Leaf) {
            [System.IO.File]::Replace($temporaryInit, $gradleInit, $backupInit)
        } else {
            [System.IO.File]::Move($temporaryInit, $gradleInit)
        }
    } finally {
        foreach ($cleanupPath in @($temporaryInit, $backupInit)) {
            if (Test-Path -LiteralPath $cleanupPath) {
                Remove-Item -LiteralPath $cleanupPath -Force
            }
        }
    }

    $syncedInitHash = (Get-FileHash -LiteralPath $gradleInit -Algorithm SHA256).Hash
    if ($syncedInitHash -ne $expectedInitHash) {
        throw "Failed to synchronize the LocalShare Gradle init script: $gradleInit"
    }
}

if ($SyncGradleInitOnly) {
    Write-Output "LocalShare Gradle init script is synchronized: $gradleInit"
    return
}

$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk
$env:GRADLE_USER_HOME = $gradleHome
$env:JAVA_HOME = $javaHome

Push-Location (Join-Path $workspace 'app')
try {
    & $flutter build apk --debug --no-pub
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Android build failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
