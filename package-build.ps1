#Requires -Version 7.4
# Copy the vcpkg tree to vcpkg_installed, drop what isn't shipped and pack it.
# Usage: ./package-build.ps1 -Triplet x86-windows -Archive gtk3.24-x86-windows.7z -Level 9

param(
    [Parameter(Mandatory)]
    [string]$Triplet,
    [Parameter(Mandatory)]
    [string]$Archive,
    [Parameter(Mandatory)]
    [ValidateRange(0, 9)]
    [int]$Level
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Get-TreeSize([string]$Path) {
    $bytes = (Get-ChildItem $Path -Recurse -File -Force | Measure-Object Length -Sum).Sum
    '{0:N1} MiB' -f ($bytes / 1MB)
}

# Copy-Item would nest the copy in an existing tree, and 7z would add to an
# existing archive
foreach ($stale in 'vcpkg_installed', $Archive) {
    if (Test-Path -LiteralPath $stale) {
        Remove-Item -LiteralPath $stale -Recurse -Force
    }
}

# Only the target triplet, not vcpkg's metadata or another tree
$tree = Join-Path vcpkg_installed $Triplet
New-Item -ItemType Directory -Path vcpkg_installed | Out-Null
Copy-Item (Join-Path vcpkg/installed $Triplet) $tree -Recurse
Write-Output "Size before cleanup: $(Get-TreeSize vcpkg_installed)"

$debug = Join-Path $tree debug
if (Test-Path $debug) {
    Remove-Item $debug -Recurse -Force
}

Get-ChildItem (Join-Path $tree bin) -Filter *.pdb | Remove-Item -Force
Write-Output "Size after cleanup: $(Get-TreeSize vcpkg_installed)"

7z a -bso0 -bsp0 -t7z -m0=LZMA2 "-mx=$Level" -mmt=on $Archive vcpkg_installed
Write-Output "$((Get-FileHash $Archive -Algorithm SHA256).Hash.ToLower())  $Archive"
