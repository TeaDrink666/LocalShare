[CmdletBinding()]
param(
    [switch]$PrepareJunctionsOnly,
    [switch]$RunElevated,
    [switch]$PubGetOnly,
    [string]$ElevatedBuildLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$appDirectory = [System.IO.Path]::GetFullPath((Join-Path $workspace 'app'))
$pluginDependencies = Join-Path $appDirectory '.flutter-plugins-dependencies'
$pluginJunctionRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $appDirectory 'windows\flutter\ephemeral\.plugin_symlinks')
)
$toolRoot = Join-Path $workspace 'LocalShare'
$buildLogRoot = Join-Path $toolRoot 'windows-build-logs'

$flutter = Join-Path $toolRoot 'flutter-3.24.5\bin\flutter.bat'
$rustRoot = 'D:\software_D\Rust'
$cargoHome = Join-Path $rustRoot '.cargo'
$rustupHome = Join-Path $rustRoot '.rustup'
$rustBin = Join-Path $cargoHome 'bin'
$cargo = Join-Path $rustBin 'cargo.exe'
$rustup = Join-Path $rustBin 'rustup.exe'

function Test-CurrentProcessIsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object System.Security.Principal.WindowsPrincipal $identity
        return $principal.IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator
        )
    } finally {
        $identity.Dispose()
    }
}

function Invoke-ElevatedBuild {
    $windowsPowerShell = Join-Path $env:SystemRoot (
        'System32\WindowsPowerShell\v1.0\powershell.exe'
    )
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        throw "Windows PowerShell is missing: $windowsPowerShell"
    }

    $logPath = New-BuildLogPath
    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ('"{0}"' -f $PSCommandPath),
        '-ElevatedBuildLog',
        ('"{0}"' -f $logPath)
    )
    if ($PubGetOnly) {
        $arguments += '-PubGetOnly'
    }

    Write-Output 'Requesting Administrator access for a hidden build worker...'
    Write-Output 'This does not enable or change Windows Developer Mode.'
    Write-Output "Elevated build log: $logPath"
    $process = $null
    try {
        $process = Start-Process `
            -FilePath $windowsPowerShell `
            -ArgumentList $arguments `
            -Verb RunAs `
            -WorkingDirectory $workspace `
            -WindowStyle Hidden `
            -PassThru
    } catch {
        throw "Administrator launch was cancelled or failed: $($_.Exception.Message)"
    }

    try {
        # Start-Process -Wait waits for the entire descendant process tree on
        # Windows. Build tools can leave helper processes alive after this
        # PowerShell worker exits, so wait on the worker handle directly.
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    } catch {
        throw "Failed while waiting for the elevated build worker: $($_.Exception.Message)"
    } finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }

    if ($exitCode -ne 0) {
        throw (
            "Elevated LocalShare Windows build failed with exit code " +
            "$exitCode. Full log: $logPath"
        )
    }
    Write-Output (
        "Elevated LocalShare Windows build completed with exit code 0. " +
        "Full log: $logPath"
    )
}

function Get-NormalizedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Equals($pathRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath
    }

    return $fullPath.TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ))
}

function Test-PathIsInside {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Parent
    )

    $normalizedPath = Get-NormalizedPath -Path $Path
    $normalizedParent = Get-NormalizedPath -Path $Parent
    $parentPrefix = $normalizedParent + [System.IO.Path]::DirectorySeparatorChar
    return $normalizedPath.StartsWith(
        $parentPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Initialize-BuildLogDirectory {
    $logParent = [System.IO.Path]::GetDirectoryName($buildLogRoot)
    if (-not (Test-Path -LiteralPath $logParent -PathType Container)) {
        throw "LocalShare build-tool directory is missing: $logParent"
    }

    $parentItem = Get-Item -LiteralPath $logParent -Force
    if (($parentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to write build logs through a reparse-point parent: $logParent"
    }

    if (Test-Path -LiteralPath $buildLogRoot -PathType Leaf) {
        throw "Windows build-log path is a file, not a directory: $buildLogRoot"
    }
    if (-not (Test-Path -LiteralPath $buildLogRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $buildLogRoot)
    }

    $logRootItem = Get-Item -LiteralPath $buildLogRoot -Force
    if (($logRootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to write build logs through a reparse point: $buildLogRoot"
    }
}

function Assert-SafeBuildLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    Initialize-BuildLogDirectory
    $normalizedLog = Get-NormalizedPath -Path $LiteralPath
    $normalizedRoot = Get-NormalizedPath -Path $buildLogRoot
    $logParent = Get-NormalizedPath -Path (
        [System.IO.Path]::GetDirectoryName($normalizedLog)
    )
    if (-not $logParent.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Elevated build logs must be direct children of $normalizedRoot`: $normalizedLog"
    }

    $fileName = [System.IO.Path]::GetFileName($normalizedLog)
    if ($fileName -notmatch '^windows-debug-\d{8}-\d{6}-[0-9a-f]{8}\.log$') {
        throw "Unexpected elevated build-log filename: $fileName"
    }
    if (Test-Path -LiteralPath $normalizedLog) {
        throw "Refusing to overwrite an existing elevated build log: $normalizedLog"
    }
    return $normalizedLog
}

function New-BuildLogPath {
    Initialize-BuildLogDirectory
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $suffix = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $path = Join-Path $buildLogRoot "windows-debug-$timestamp-$suffix.log"
    return Assert-SafeBuildLogPath -LiteralPath $path
}

function Get-FileSystemEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    return Get-Item -LiteralPath $LiteralPath -Force -ErrorAction SilentlyContinue
}

function Assert-OrdinaryDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $item = Get-FileSystemEntry -LiteralPath $LiteralPath
    if ($null -eq $item) {
        [void](New-Item -ItemType Directory -Path $LiteralPath)
        $item = Get-FileSystemEntry -LiteralPath $LiteralPath
    }

    if ($null -eq $item -or -not $item.PSIsContainer) {
        throw "Required junction parent is not a directory: $LiteralPath"
    }

    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to use a reparse point as a junction parent: $LiteralPath"
    }
}

function Assert-SafeJunctionPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $normalizedPath = Get-NormalizedPath -Path $LiteralPath
    $normalizedRoot = Get-NormalizedPath -Path $pluginJunctionRoot
    if (-not (Test-PathIsInside -Path $normalizedPath -Parent $normalizedRoot)) {
        throw "Refusing to modify a path outside the plugin junction directory: $normalizedPath"
    }

    $parent = Get-NormalizedPath -Path ([System.IO.Path]::GetDirectoryName($normalizedPath))
    if (-not $parent.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Plugin junctions must be direct children of $normalizedRoot`: $normalizedPath"
    }

    return $normalizedPath
}

function Remove-SafeDirectoryReparsePoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $safePath = Assert-SafeJunctionPath -LiteralPath $LiteralPath
    $item = Get-FileSystemEntry -LiteralPath $safePath
    if ($null -eq $item) {
        return
    }

    $isReparsePoint =
        ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    if (-not $item.PSIsContainer -or -not $isReparsePoint) {
        throw "Refusing to delete a non-reparse directory entry: $safePath"
    }

    # Directory.Delete removes the junction itself and never traverses its target.
    [System.IO.Directory]::Delete($safePath, $false)
    if ($null -ne (Get-FileSystemEntry -LiteralPath $safePath)) {
        throw "Failed to remove plugin reparse point: $safePath"
    }
}

function Get-ReparsePointTarget {
    param(
        [Parameter(Mandatory = $true)]
        $Item
    )

    $targetProperty = $Item.PSObject.Properties['Target']
    if ($null -eq $targetProperty) {
        return $null
    }

    $targets = @($targetProperty.Value)
    if ($targets.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$targets[0])) {
        return $null
    }

    $target = [string]$targets[0]
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path $Item.Parent.FullName $target
    }
    return Get-NormalizedPath -Path $target
}

function Ensure-PluginJunction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $junctionPath = Assert-SafeJunctionPath -LiteralPath (Join-Path $pluginJunctionRoot $Name)
    $normalizedTarget = Get-NormalizedPath -Path $Target
    $item = Get-FileSystemEntry -LiteralPath $junctionPath

    if ($null -ne $item) {
        $linkTypeProperty = $item.PSObject.Properties['LinkType']
        $linkType = if ($null -eq $linkTypeProperty) {
            $null
        } else {
            [string]$linkTypeProperty.Value
        }
        $existingTarget = Get-ReparsePointTarget -Item $item
        $targetMatches =
            $null -ne $existingTarget -and
            $existingTarget.Equals(
                $normalizedTarget,
                [System.StringComparison]::OrdinalIgnoreCase
            )

        if ($linkType -eq 'Junction' -and $targetMatches) {
            return $false
        }

        Remove-SafeDirectoryReparsePoint -LiteralPath $junctionPath
    }

    [void](New-Item -ItemType Junction -Path $junctionPath -Target $normalizedTarget)

    $created = Get-FileSystemEntry -LiteralPath $junctionPath
    $createdLinkTypeProperty = $created.PSObject.Properties['LinkType']
    $createdLinkType = if ($null -eq $createdLinkTypeProperty) {
        $null
    } else {
        [string]$createdLinkTypeProperty.Value
    }
    $createdTarget = Get-ReparsePointTarget -Item $created
    if (
        $createdLinkType -ne 'Junction' -or
        $null -eq $createdTarget -or
        -not $createdTarget.Equals(
            $normalizedTarget,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "Failed to verify plugin junction: $junctionPath -> $normalizedTarget"
    }

    return $true
}

$hasElevatedBuildLog = -not [string]::IsNullOrWhiteSpace($ElevatedBuildLog)
if ($PrepareJunctionsOnly -and ($RunElevated -or $PubGetOnly -or $hasElevatedBuildLog)) {
    throw '-PrepareJunctionsOnly cannot be combined with elevated-build parameters.'
}
if ($RunElevated -and $hasElevatedBuildLog) {
    throw '-ElevatedBuildLog is reserved for the elevated worker.'
}

if (-not $PrepareJunctionsOnly -and -not (Test-CurrentProcessIsAdministrator)) {
    if ($RunElevated) {
        Invoke-ElevatedBuild
        return
    }

    throw (
        'Flutter 3.24.5 requires real directory symlinks for Windows plugins. ' +
        'Run this script from an Administrator PowerShell terminal, or rerun ' +
        'with -RunElevated to request UAC elevation. This script does not ' +
        'enable or change Windows Developer Mode.'
    )
}

$transcriptStarted = $false
if ($hasElevatedBuildLog) {
    $ElevatedBuildLog = Assert-SafeBuildLogPath -LiteralPath $ElevatedBuildLog
    [void](Start-Transcript -LiteralPath $ElevatedBuildLog -NoClobber)
    $transcriptStarted = $true
    Write-Output "LocalShare elevated Windows build log: $ElevatedBuildLog"
}

try {
if (-not (Test-Path -LiteralPath $appDirectory -PathType Container)) {
    throw "LocalShare app directory is missing: $appDirectory"
}
if (-not (Test-PathIsInside -Path $appDirectory -Parent $workspace)) {
    throw "The LocalShare app directory is outside the workspace: $appDirectory"
}
if (-not (Test-PathIsInside -Path $pluginJunctionRoot -Parent $appDirectory)) {
    throw "The plugin junction directory is outside the LocalShare app: $pluginJunctionRoot"
}

# Reject reparse points in the managed path so a junction refresh cannot escape
# the workspace through a redirected parent directory.
Assert-OrdinaryDirectory -LiteralPath $appDirectory
$managedParent = $appDirectory
foreach ($segment in @('windows', 'flutter', 'ephemeral', '.plugin_symlinks')) {
    $managedParent = Join-Path $managedParent $segment
    Assert-OrdinaryDirectory -LiteralPath $managedParent
}

if (-not (Test-Path -LiteralPath $pluginDependencies -PathType Leaf)) {
    throw "Flutter plugin dependency manifest is missing: $pluginDependencies"
}

try {
    $manifest = Get-Content -LiteralPath $pluginDependencies -Raw | ConvertFrom-Json
} catch {
    throw "Failed to parse Flutter plugin dependency manifest '$pluginDependencies': $($_.Exception.Message)"
}

$windowsPlugins = @($manifest.plugins.windows)
if ($windowsPlugins.Count -eq 0) {
    throw "No Windows plugins were found in $pluginDependencies"
}

$pluginRecords = @()
$expectedNames = New-Object 'System.Collections.Generic.HashSet[string]' (
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($plugin in $windowsPlugins) {
    $name = [string]$plugin.name
    $targetText = [string]$plugin.path
    if ($name -notmatch '^[A-Za-z0-9_]+$') {
        throw "Unsafe Windows plugin name in dependency manifest: '$name'"
    }
    if (-not $expectedNames.Add($name)) {
        throw "Duplicate Windows plugin name in dependency manifest: '$name'"
    }
    if ([string]::IsNullOrWhiteSpace($targetText)) {
        throw "Windows plugin '$name' has no source path in the dependency manifest."
    }

    $target = Get-NormalizedPath -Path $targetText
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        throw "Windows plugin '$name' source directory is missing: $target"
    }

    $nativeBuild = $false
    $nativeBuildProperty = $plugin.PSObject.Properties['native_build']
    if ($null -ne $nativeBuildProperty) {
        $nativeBuild = [bool]$nativeBuildProperty.Value
    }

    $pluginRecords += [pscustomobject]@{
        Name = $name
        Target = $target
        NativeBuild = $nativeBuild
    }
}

if ($PrepareJunctionsOnly) {
    $removedCount = 0
    foreach ($existing in @(Get-ChildItem -LiteralPath $pluginJunctionRoot -Force)) {
        if ($expectedNames.Contains($existing.Name)) {
            continue
        }

        $isReparsePoint =
            ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        if (-not $existing.PSIsContainer -or -not $isReparsePoint) {
            throw "Refusing to delete unexpected non-junction entry: $($existing.FullName)"
        }

        Remove-SafeDirectoryReparsePoint -LiteralPath $existing.FullName
        $removedCount++
    }

    $createdCount = 0
    foreach ($plugin in $pluginRecords) {
        if (Ensure-PluginJunction -Name $plugin.Name -Target $plugin.Target) {
            $createdCount++
        }
    }

    $nativeCount = @($pluginRecords | Where-Object { $_.NativeBuild }).Count
    $platformOnlyCount = $pluginRecords.Count - $nativeCount
    $summary =
        'Prepared {0} diagnostic Windows plugin junctions ' +
        '({1} native/FFI, {2} platform-only); {3} created/refreshed, ' +
        '{4} stale removed.'
    Write-Output ($summary -f
        $pluginRecords.Count,
        $nativeCount,
        $platformOnlyCount,
        $createdCount,
        $removedCount
    )
    Write-Output "Plugin junction directory is ready: $pluginJunctionRoot"
    Write-Warning (
        'Directory junctions are diagnostic only. Flutter dart:io does not ' +
        'recognize them as plugin Links, so they cannot replace Administrator ' +
        'access or Developer Mode for a Windows build.'
    )
    return
}

foreach ($requiredTool in @($flutter, $cargo, $rustup)) {
    if (-not (Test-Path -LiteralPath $requiredTool -PathType Leaf)) {
        throw "Required LocalShare Windows build dependency is missing: $requiredTool"
    }
}
if (-not (Test-Path -LiteralPath $rustupHome -PathType Container)) {
    throw "Required LocalShare Rust toolchain directory is missing: $rustupHome"
}

# Flutter checks plugin paths with dart:io Link.existsSync. NTFS junctions are
# reported as directories, not Links, so remove all managed reparse entries and
# let the elevated Flutter process create real directory symbolic links.
$removedForBuild = 0
foreach ($existing in @(Get-ChildItem -LiteralPath $pluginJunctionRoot -Force)) {
    $isReparsePoint =
        ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    if (-not $existing.PSIsContainer -or -not $isReparsePoint) {
        throw "Refusing to delete unexpected non-reparse entry: $($existing.FullName)"
    }

    Remove-SafeDirectoryReparsePoint -LiteralPath $existing.FullName
    $removedForBuild++
}
Write-Output (
    "Removed $removedForBuild managed plugin reparse entries before the elevated build."
)

$env:CARGO_HOME = $cargoHome
$env:RUSTUP_HOME = $rustupHome
$env:PATH = $rustBin + [System.IO.Path]::PathSeparator + $env:PATH

Push-Location $appDirectory
try {
    if ($PubGetOnly) {
        & $flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter pub get failed with exit code $LASTEXITCODE."
        }
        return
    }
    & $flutter build windows --debug --no-pub
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Windows build failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
if ($transcriptStarted) {
    Write-Output 'LocalShare elevated Windows build completed successfully.'
}
} catch {
    if ($transcriptStarted) {
        Write-Error (
            "LocalShare elevated Windows build failed: $($_.Exception.Message)"
        ) -ErrorAction Continue
    }
    throw
} finally {
    if ($transcriptStarted) {
        try {
            [void](Stop-Transcript)
        } catch {
            Write-Warning "Failed to close Windows build transcript: $($_.Exception.Message)"
        }
    }
}
