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

Copy-Item vcpkg/installed vcpkg_installed -Recurse
Write-Output "Size before cleanup: $(Get-TreeSize vcpkg_installed)"

$tree = Join-Path vcpkg_installed $Triplet
$debug = Join-Path $tree debug
if (Test-Path $debug) {
    Remove-Item $debug -Recurse -Force
}

Get-ChildItem (Join-Path $tree bin) -Filter *.pdb | Remove-Item -Force
# Keep only the target triplet, not vcpkg's metadata or another tree
Get-ChildItem vcpkg_installed -Force | Where-Object Name -ne $Triplet | Remove-Item -Recurse -Force
Write-Output "Size after cleanup: $(Get-TreeSize vcpkg_installed)"

7z a -bso0 -bsp0 -t7z "-mx=$Level" -mmt=on $Archive vcpkg_installed
Write-Output "$((Get-FileHash $Archive -Algorithm SHA256).Hash.ToLower())  $Archive"
