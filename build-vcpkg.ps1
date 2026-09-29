#Requires -Version 7.4
# Patch the vcpkg checkout at ./vcpkg and build Python and the GTK stack.
# Usage: ./build-vcpkg.ps1 -Triplet x86-windows

param(
    [Parameter(Mandatory)]
    [string]$Triplet,
    # Drop archives this build didn't use and output the ABI hash for the CI cache key
    [switch]$PruneCache
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$patches = Join-Path $PSScriptRoot 'patches'
$ports = @(
    'python3'
    'fontconfig[tools]'
    'gobject-introspection'
    'harfbuzz[introspection]'
    'pango[introspection]'
    'gdk-pixbuf[introspection]'
    'atk[introspection]'
    'libcroco'
    'librsvg'
    'gtk3[introspection]'
)

Push-Location (Join-Path $PSScriptRoot 'vcpkg')
try {
    foreach ($patch in '0002-vcpkg-glib-unc.patch', 'gdk-pixbuf-png-only.patch') {
        git apply --ignore-whitespace --whitespace=nowarn (Join-Path $patches $patch)
    }

    Copy-Item (Join-Path $patches 'librsvg-pixbufloader-svg.patch') ./ports/librsvg/add-pixbufloader-svg.patch
    (Get-Content ./ports/librsvg/portfile.cmake) -replace 'meson-pkgconfig-and-def-file\.patch', "meson-pkgconfig-and-def-file.patch`n        add-pixbufloader-svg.patch" | Set-Content ./ports/librsvg/portfile.cmake

    ./bootstrap-vcpkg.bat
    ./vcpkg format-manifest ports/gdk-pixbuf/vcpkg.json
    git add ports/gdk-pixbuf
    ./vcpkg x-add-version gdk-pixbuf

    $cacheDir = Join-Path $env:LOCALAPPDATA 'vcpkg\archives'
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    ./vcpkg install @ports --triplet $Triplet "--binarysource=clear;files,$cacheDir,readwrite"

    if ($PruneCache) {
        # Archives are stored as <cacheDir>/<ab>/<abi>.zip
        $abis = Select-String -LiteralPath ./installed/vcpkg/status -Pattern '^Abi: (\w+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object
        $stale = Get-ChildItem $cacheDir -Recurse -Filter *.zip | Where-Object BaseName -notin $abis
        $stale | Remove-Item
        Write-Host "Removed $(@($stale).Count) stale archives, $($abis.Count) packages installed"

        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($abis -join "`n"))).ToLower()
        if ($env:GITHUB_OUTPUT) {
            Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "abi-hash=$hash"
        }
    }
}
finally {
    Pop-Location
}
