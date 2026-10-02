#Requires -Version 7.4
# Install the PyGObject wheel into the GTK build's Python and check that it
# loads GTK and the platform-specific typelibs without warnings. Needs the
# pygtkwin-env variables.
# Usage: ./test-pygobject.ps1 -Wheel <path to .whl>

param(
    [Parameter(Mandatory)]
    [string]$Wheel
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# pycairo, its only dependency, comes pinned from requirements.txt. A rebuilt
# wheel keeps its version, so pip has to replace the installed one.
& $env:PYTHON -m pip install --no-deps --force-reinstall $Wheel

$bin = Join-Path $env:VCPKG_DIR 'bin'
$typelibs = Join-Path $env:VCPKG_DIR 'lib\girepository-1.0'
$pythonTypelibs = Join-Path $env:PYTHON_DIR 'lib\girepository-1.0'
New-Item -ItemType Directory -Force -Path $pythonTypelibs | Out-Null
Copy-Item (Join-Path $typelibs '*') $pythonTypelibs -Recurse -Force

$env:PATH = "$env:PATH;$bin;$(Join-Path $env:VCPKG_DIR 'lib')"
$env:GI_TYPELIB_PATH = $typelibs
& $env:PYTHON (Join-Path $PSScriptRoot 'show_versions.py') "--dll-directory=$bin"

# GLib reports platform typelib problems as warnings, not errors
$log = New-TemporaryFile
try {
    & $env:PYTHON (Join-Path $PSScriptRoot 'test_platform_typelibs.py') "--dll-directory=$bin" 2> $log.FullName
}
finally {
    Get-Content -LiteralPath $log.FullName
}

$warnings = 'Unable to load platform-specific GIO introspection data', 'Name conflict for platform-specific symbol'
if (Select-String -LiteralPath $log.FullName -SimpleMatch -Quiet -Pattern $warnings) {
    throw 'Platform-specific typelib regression detected'
}
