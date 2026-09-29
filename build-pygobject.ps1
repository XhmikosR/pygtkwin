#Requires -Version 7.4
# Build the PyGObject wheel against the extracted GTK build and export its
# path as PYGOBJECT_WHL. Needs the pygtkwin-env variables, PYGOBJECT_VERSION
# and PYGOBJECT_SHA256.
# Usage: ./build-pygobject.ps1 -WheelTag win32

param(
    [Parameter(Mandatory)]
    [ValidateSet('win32', 'win_amd64')]
    [string]$WheelTag
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if (-not (Test-Path -LiteralPath $env:PYTHON -PathType Leaf)) {
    throw "Python executable not found at $env:PYTHON"
}

$version = $env:PYGOBJECT_VERSION
$series = ($version -split '\.')[0..1] -join '.'
$tarball = 'pygobject.tar.gz'
Invoke-WebRequest "https://download.gnome.org/sources/pygobject/$series/pygobject-$version.tar.gz" -OutFile $tarball
$hash = (Get-FileHash $tarball -Algorithm SHA256).Hash
Write-Output "SHA256 $tarball $hash"
if ($hash -ne $env:PYGOBJECT_SHA256) {
    throw "SHA256 mismatch for $tarball, expected $env:PYGOBJECT_SHA256"
}
tar -xf $tarball

# The GTK build's Python ships without pip
& $env:PYTHON -m ensurepip --upgrade
& $env:PYTHON -m pip install --upgrade pip
& $env:PYTHON -m pip install --no-deps -r (Join-Path $PSScriptRoot 'requirements.txt')
# No pip check: the pkgconf Windows wheel's metadata claims linux_x86_64

$libs = Join-Path $env:PYTHON_DIR 'libs'
New-Item -ItemType Directory -Force -Path $libs | Out-Null
Copy-Item (Join-Path $env:VCPKG_DIR 'lib\python312.lib') $libs

# meson needs cl, and only this step builds C code outside vcpkg
$vsPath = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vsArch = if ($WheelTag -eq 'win_amd64') { 'amd64' } else { 'x86' }
Import-Module (Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation -DevCmdArguments "-arch=$vsArch -host_arch=amd64"

$env:PKG_CONFIG = Join-Path $env:VCPKG_DIR 'tools\python3\Lib\site-packages\pkgconf\.bin\pkgconf.exe'
$env:PKG_CONFIG_PATH = Join-Path $env:VCPKG_DIR 'lib\pkgconfig'
$env:CC = 'cl'
$env:CXX = 'cl'
$env:CL = "$(& $env:PKG_CONFIG --cflags python-3.12)".Trim()

$source = Join-Path $PWD "pygobject-$version"
Push-Location $source
try {
    # The build dependencies are pinned in requirements.txt
    & $env:PYTHON -m build --wheel --no-isolation
}
finally {
    Pop-Location
}

$wheel = Join-Path $source "dist\pygobject-$version-cp312-cp312-$WheelTag.whl"
if (-not (Test-Path -LiteralPath $wheel -PathType Leaf)) {
    throw "$wheel does not exist"
}
Write-Output "Built $wheel"
if ($env:GITHUB_ENV) {
    Add-Content -LiteralPath $env:GITHUB_ENV -Value "PYGOBJECT_WHL=$wheel"
}
