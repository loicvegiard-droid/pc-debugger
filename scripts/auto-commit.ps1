<#
.SYNOPSIS
    Auto-commit watcher for pc-debugger.
    Run this once in a background terminal — it watches for file changes
    and auto-commits + pushes to GitHub every time you save.

.USAGE
    cd C:\Users\loicv\pc-debugger
    .\scripts\auto-commit.ps1

    Options:
    -DebounceSeconds 10    # wait N seconds after last change before committing (default: 10)
    -NoPush                # commit locally only, don't push
    -WatchPath "."         # folder to watch (default: repo root)

.DESCRIPTION
    Uses PowerShell FileSystemWatcher for real-time change detection.
    Debounces rapid saves to avoid spam commits.
    Skips .git/ folder, *.lock files, and __pycache__.
    Each auto-commit is tagged [auto] so the nightly compact can squash them.
#>

param(
    [int]$DebounceSeconds = 10,
    [switch]$NoPush,
    [string]$WatchPath = $PSScriptRoot | Split-Path
)

$RepoRoot = $WatchPath
Set-Location $RepoRoot

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host " pc-debugger — Auto-Commit Watcher" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host " Watching : $RepoRoot"
Write-Host " Debounce : ${DebounceSeconds}s after last change"
Write-Host " Push     : $(-not $NoPush)"
Write-Host " Ctrl+C to stop"
Write-Host ""

# --- Watcher setup ---
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $RepoRoot
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName

# Patterns to ignore
$ignorePatterns = @('.git', '__pycache__', '.mypy_cache', '.ruff_cache', '*.lock', '*.pyc', '.uv')

$global:PendingCommit = $false
$global:LastChange = [datetime]::MinValue
$global:ChangedFiles = [System.Collections.Generic.HashSet[string]]::new()

function Should-Ignore($path) {
    foreach ($pattern in $ignorePatterns) {
        if ($path -like "*$pattern*") { return $true }
    }
    return $false
}

$action = {
    $path = $Event.SourceEventArgs.FullPath
    if (-not (Should-Ignore $path)) {
        $global:PendingCommit = $true
        $global:LastChange = [datetime]::Now
        $rel = $path.Replace($RepoRoot + '\', '')
        $null = $global:ChangedFiles.Add($rel)
    }
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null
Register-ObjectEvent $watcher Deleted -Action $action | Out-Null
Register-ObjectEvent $watcher Renamed -Action $action | Out-Null

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Watching for changes..." -ForegroundColor Green

# --- Main loop ---
try {
    while ($true) {
        Start-Sleep -Milliseconds 500

        if ($global:PendingCommit) {
            $elapsed = ([datetime]::Now - $global:LastChange).TotalSeconds
            if ($elapsed -ge $DebounceSeconds) {
                $global:PendingCommit = $false

                # Check if there's anything to commit
                $status = git -C $RepoRoot status --porcelain
                if ($status) {
                    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    $files = ($global:ChangedFiles | Select-Object -First 5) -join ', '
                    $global:ChangedFiles.Clear()

                    $msg = "[auto] $timestamp — $files"
                    if ($global:ChangedFiles.Count -gt 5) { $msg += " +more" }

                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Committing: $msg" -ForegroundColor Yellow

                    git -C $RepoRoot add -A
                    git -C $RepoRoot commit -m $msg --quiet

                    if (-not $NoPush) {
                        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Pushing..." -ForegroundColor DarkYellow
                        git -C $RepoRoot push --quiet
                        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Pushed ✓" -ForegroundColor Green
                    } else {
                        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Committed locally (no push)" -ForegroundColor Green
                    }
                } else {
                    $global:ChangedFiles.Clear()
                }
            }
        }
    }
} finally {
    $watcher.Dispose()
    Write-Host "`nWatcher stopped." -ForegroundColor Red
}
