#Requires -Version 7.4
# Build the PyGObject wheel against the extracted GTK build and export its
# path as PYGOBJECT_WHL. Needs the pygtkwin-env variables. The version and
# hashes come from requirements-pygobject.txt, which Dependabot updates.
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

# For example 3.12 and 312
$pyVersion = & $env:PYTHON -c 'import sysconfig; print(sysconfig.get_python_version())'
$pyTag = $pyVersion.Replace('.', '')

$requirement = Get-Content (Join-Path $PSScriptRoot 'requirements-pygobject.txt') -Raw
if ($requirement -notmatch '(?mi)^pygobject==(\S+)') {
    throw 'No pygobject pin in requirements-pygobject.txt'
}
$version = $Matches[1]
# One hash per file on PyPI, so this also accepts wheels if they ever appear
$hashes = [regex]::Matches($requirement, '--hash=sha256:([0-9a-f]{64})') | ForEach-Object { $_.Groups[1].Value }
if (-not $hashes) {
    throw 'No hashes in requirements-pygobject.txt'
}

$tarball = 'pygobject.tar.gz'
Invoke-WebRequest "https://files.pythonhosted.org/packages/source/p/pygobject/pygobject-$version.tar.gz" -OutFile $tarball -MaximumRetryCount 3 -RetryIntervalSec 5
$hash = (Get-FileHash $tarball -Algorithm SHA256).Hash
Write-Output "SHA256 $tarball $hash"
if ($hashes -notcontains $hash) {
    throw "SHA256 mismatch for $tarball, expected one of $($hashes -join ', ')"
}
tar -xf $tarball

# The GTK build's Python ships without pip. The bundled one is enough and
# stays pinned through the vcpkg commit.
& $env:PYTHON -m ensurepip --upgrade
& $env:PYTHON -m pip install --no-deps -r (Join-Path $PSScriptRoot 'requirements.txt')
# No pip check: the pkgconf Windows wheel's metadata claims linux_x86_64

$libs = Join-Path $env:PYTHON_DIR 'libs'
New-Item -ItemType Directory -Force -Path $libs | Out-Null
Copy-Item (Join-Path $env:VCPKG_DIR "lib\python$pyTag.lib") $libs

# meson needs cl, and only this step builds C code outside vcpkg
$vsPath = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vsArch = if ($WheelTag -eq 'win_amd64') { 'amd64' } else { 'x86' }
Import-Module (Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation -DevCmdArguments "-arch=$vsArch -host_arch=amd64"

$env:PKG_CONFIG = Join-Path $env:VCPKG_DIR 'tools\python3\Lib\site-packages\pkgconf\.bin\pkgconf.exe'
$env:PKG_CONFIG_PATH = Join-Path $env:VCPKG_DIR 'lib\pkgconfig'
$env:CC = 'cl'
$env:CXX = 'cl'
$env:CL = "$(& $env:PKG_CONFIG --cflags "python-$pyVersion")".Trim()

$source = Join-Path $PWD "pygobject-$version"
Push-Location $source
try {
    # The link flags match the vcpkg triplets
    $config = "-Dc_link_args=['/RELEASE','/OPT:REF','/OPT:ICF']" |
        ForEach-Object { "--config-setting=setup-args=$_" }
    # The build dependencies are pinned in requirements.txt
    & $env:PYTHON -m build --wheel --no-isolation @config
}
finally {
    Pop-Location
}

$wheel = Join-Path $source "dist\pygobject-$version-cp$pyTag-cp$pyTag-$WheelTag.whl"
if (-not (Test-Path -LiteralPath $wheel -PathType Leaf)) {
    throw "$wheel does not exist"
}
Write-Output "Built $wheel"
if ($env:GITHUB_ENV) {
    Add-Content -LiteralPath $env:GITHUB_ENV -Value "PYGOBJECT_WHL=$wheel"
}
