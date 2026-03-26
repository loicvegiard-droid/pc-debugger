<#
.SYNOPSIS
    Single entry point for pc-debugger agentic workflow.
    Run this ONCE when you open your terminal. Everything else is automatic.

.USAGE
    C:\Users\loicv\pc-debugger\scripts\start.ps1
#>

$RepoRoot = $PSScriptRoot | Split-Path
Set-Location $RepoRoot

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host " pc-debugger — Agentic Workspace" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# 1. AUTO-RESUME: pull latest from GitHub
Write-Host "`n[1/3] Auto-resume: syncing with GitHub..." -ForegroundColor DarkYellow
git -C $RepoRoot pull --rebase --quiet
Write-Host "      Up to date." -ForegroundColor Green

# 2. SHOW STATE: last 5 commits so you know where you are
Write-Host "`n[2/3] Current state (last 5 commits):" -ForegroundColor DarkYellow
git -C $RepoRoot log --oneline -5 --format="      %C(yellow)%h%Creset %C(dim)%ar%Creset  %s"

# 3. AUTO-COMMIT: start watcher in background job
Write-Host "`n[3/3] Starting auto-commit watcher in background..." -ForegroundColor DarkYellow
$watcherJob = Start-Job -ScriptBlock {
    param($root)
    & "$root\scripts\auto-commit.ps1" -WatchPath $root
} -ArgumentList $RepoRoot

Write-Host "      Watcher running (Job ID: $($watcherJob.Id))" -ForegroundColor Green

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host " Ready. Every save auto-commits to GitHub." -ForegroundColor Green
Write-Host " Rollback anytime: .\scripts\rollback.ps1" -ForegroundColor DarkGray
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
