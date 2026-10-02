#Requires -Version 7.4
# Patch the vcpkg checkout at ./vcpkg and build Python and the GTK stack.
# CI runs -Phase Prepare and -Phase Install as separate steps, so it can
# restore the binary cache keyed on the ABI hash that Prepare outputs.
# Usage: ./build-vcpkg.ps1 -Triplet x86-windows

param(
    [Parameter(Mandatory)]
    [string]$Triplet,
    [ValidateSet('All', 'Prepare', 'Install')]
    [string]$Phase = 'All',
    # Drop archives this build didn't use
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

$cacheDir = Join-Path $env:LOCALAPPDATA 'vcpkg\archives'
$binarySource = "--binarysource=clear;files,$cacheDir,readwrite"
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

Push-Location (Join-Path $PSScriptRoot 'vcpkg')
try {
    if ($Phase -ne 'Install') {
        foreach ($patch in '0002-vcpkg-glib-unc.patch', 'gdk-pixbuf-png-only.patch') {
            git apply --ignore-whitespace --whitespace=nowarn (Join-Path $patches $patch)
        }

        Copy-Item (Join-Path $patches 'librsvg-pixbufloader-svg.patch') ./ports/librsvg/add-pixbufloader-svg.patch
        (Get-Content ./ports/librsvg/portfile.cmake) -replace 'meson-pkgconfig-and-def-file\.patch', "meson-pkgconfig-and-def-file.patch`n        add-pixbufloader-svg.patch" | Set-Content ./ports/librsvg/portfile.cmake

        ./bootstrap-vcpkg.bat -disableMetrics
        ./vcpkg format-manifest ports/gdk-pixbuf/vcpkg.json
        git add ports/gdk-pixbuf
        ./vcpkg x-add-version gdk-pixbuf
    }

    if ($Phase -eq 'Prepare') {
        # Lists every package with its ABI hash without building anything
        ./vcpkg install @ports --triplet $Triplet --dry-run $binarySource '--x-write-nuget-packages-config=abi.config'
        $hash = (Get-FileHash abi.config -Algorithm SHA256).Hash.ToLower()
        Write-Host "ABI hash: $hash"
        if ($env:GITHUB_OUTPUT) {
            Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "abi-hash=$hash"
        }
    }

    if ($Phase -ne 'Prepare') {
        ./vcpkg install @ports --triplet $Triplet $binarySource

        if ($PruneCache) {
            # Archives are stored as <cacheDir>/<ab>/<abi>.zip
            $abis = Select-String -LiteralPath ./installed/vcpkg/status -Pattern '^Abi: (\w+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value }
            $stale = Get-ChildItem $cacheDir -Recurse -Filter *.zip | Where-Object BaseName -notin $abis
            $stale | Remove-Item
            Write-Host "Removed $(@($stale).Count) stale archives, $($abis.Count) packages installed"
        }
    }
}
finally {
    Pop-Location
}
