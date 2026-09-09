<#
.SYNOPSIS
  Save a timestamped local backup of index.html into backups\.

.EXAMPLE
  .\snapshot.ps1                     # backups\index-20260909-174500.html
  .\snapshot.ps1 "before-qr-rewrite" # backups\index-20260909-174500-before-qr-rewrite.html
  .\snapshot.ps1 -List               # show existing snapshots
  .\snapshot.ps1 -Restore backups\index-20260909-174500.html
#>
param(
  [string]$Label = "",
  [switch]$List,
  [string]$Restore = ""
)

$ErrorActionPreference = "Stop"
$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$source   = Join-Path $root "index.html"
$backups  = Join-Path $root "backups"

if (-not (Test-Path $backups)) { New-Item -ItemType Directory $backups | Out-Null }

if ($List) {
  Get-ChildItem $backups -Filter "index-*.html" |
    Sort-Object LastWriteTime -Descending |
    Select-Object Name, @{n="KB";e={[math]::Round($_.Length/1KB,1)}}, LastWriteTime |
    Format-Table -AutoSize
  return
}

if ($Restore) {
  if (-not (Test-Path $Restore)) { throw "No such snapshot: $Restore" }
  # Snapshot the current state first so a restore is never destructive.
  $safety = Join-Path $backups ("index-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-pre-restore.html")
  Copy-Item $source $safety
  Copy-Item $Restore $source -Force
  Write-Host "Restored $Restore -> index.html"
  Write-Host "Previous state saved to $safety"
  return
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$name  = if ($Label) { "index-$stamp-$($Label -replace '[^A-Za-z0-9._-]','-').html" } else { "index-$stamp.html" }
$dest  = Join-Path $backups $name
Copy-Item $source $dest

# Record which commit the snapshot corresponds to, for cross-referencing git history.
$sha = (git -C $root rev-parse --short HEAD 2>$null)
$dirty = if ((git -C $root status --porcelain -- index.html 2>$null)) { " +uncommitted" } else { "" }
Add-Content (Join-Path $backups "MANIFEST.txt") "$name`t$stamp`t$sha$dirty`t$Label"

Write-Host "Saved $dest  (at commit $sha$dirty)"
