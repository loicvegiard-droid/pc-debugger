<#
.SYNOPSIS
    Interactive rollback menu for pc-debugger.
    Shows recent commits and lets you safely restore to any point.

.USAGE
    cd C:\Users\loicv\pc-debugger
    .\scripts\rollback.ps1

    Options:
    -Last 20          # how many commits to show (default: 20)
    -Hash "abc1234"   # roll back directly to a specific commit hash
#>

param(
    [int]$Last = 20,
    [string]$Hash = ""
)

$RepoRoot = $PSScriptRoot | Split-Path
Set-Location $RepoRoot

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host " pc-debugger — Rollback Menu" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# Direct hash rollback
if ($Hash) {
    Write-Host "`nRolling back to: $Hash" -ForegroundColor Yellow
    $confirm = Read-Host "Confirm? This creates a safe restore commit. (y/N)"
    if ($confirm -eq 'y') {
        git -C $RepoRoot revert --no-commit "$Hash..HEAD"
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        git -C $RepoRoot commit -m "[restore] $ts — rolled back to $Hash"
        git -C $RepoRoot push
        Write-Host "Done. Rolled back safely (old history preserved)." -ForegroundColor Green
    }
    return
}

# --- Fetch latest from GitHub first ---
Write-Host "`nFetching latest from GitHub..." -ForegroundColor DarkYellow
git -C $RepoRoot fetch --quiet

# --- Show commit log ---
Write-Host "`nRecent commits (newest first):`n" -ForegroundColor White

$commits = git -C $RepoRoot log --oneline -$Last --format="%H|%ar|%s" 2>$null
if (-not $commits) {
    Write-Host "No commits found." -ForegroundColor Red
    return
}

$list = @()
$i = 0
foreach ($line in $commits) {
    $parts = $line -split '\|', 3
    $hash   = $parts[0].Substring(0, 7)
    $when   = $parts[1]
    $msg    = $parts[2]

    # Color-code auto vs manual commits
    $isAuto = $msg.StartsWith('[auto]')
    $isRestore = $msg.StartsWith('[restore]')
    $color = if ($isAuto) { 'DarkGray' } elseif ($isRestore) { 'Cyan' } else { 'White' }
    $tag = if ($isAuto) { '[auto]  ' } elseif ($isRestore) { '[restore]' } else { '[manual] ' }

    Write-Host ("  {0,2}. " -f $i) -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0} " -f $hash) -NoNewline -ForegroundColor Yellow
    Write-Host ("{0,-10} " -f $when) -NoNewline -ForegroundColor DarkGray
    Write-Host $tag -NoNewline -ForegroundColor $color
    Write-Host ($msg -replace '^\[auto\] |\[restore\] |\[manual\] ', '') -ForegroundColor $color

    $list += [pscustomobject]@{ Index = $i; Hash = $parts[0]; Message = $msg }
    $i++
}

Write-Host ""
Write-Host "  Enter number to restore, or press Enter to cancel:" -ForegroundColor DarkYellow
$choice = Read-Host "  >"

if ($choice -match '^\d+$') {
    $selected = $list[$choice]
    if ($null -eq $selected) {
        Write-Host "Invalid selection." -ForegroundColor Red
        return
    }

    Write-Host "`nSelected: [$($selected.Hash.Substring(0,7))] $($selected.Message)" -ForegroundColor Yellow
    Write-Host "This will create a NEW restore commit (your history is safe)." -ForegroundColor DarkYellow
    $confirm = Read-Host "Confirm rollback? (y/N)"

    if ($confirm -eq 'y') {
        # Safe rollback: revert all commits from selected point to HEAD
        git -C $RepoRoot revert --no-commit "$($selected.Hash)..HEAD"

        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $shortHash = $selected.Hash.Substring(0, 7)
        git -C $RepoRoot commit -m "[restore] $ts — back to $shortHash: $($selected.Message)"
        git -C $RepoRoot push

        Write-Host "`nRollback complete!" -ForegroundColor Green
        Write-Host "Your repo is now at the state of commit $shortHash." -ForegroundColor Green
        Write-Host "All intermediate history is preserved on GitHub." -ForegroundColor DarkGray
    } else {
        Write-Host "Cancelled." -ForegroundColor DarkGray
    }
} else {
    Write-Host "Cancelled." -ForegroundColor DarkGray
}
