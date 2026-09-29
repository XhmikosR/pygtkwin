#Requires -Version 7.4
# Export the build name and the paths of the GTK build and its Python

$ErrorActionPreference = 'Stop'

$gtkBuildName = "gtk$env:GTK_VERSION-$env:VCPKG_TRIPLET"
[System.IO.File]::AppendAllText($env:GITHUB_ENV, "GTK_BUILD_NAME=$gtkBuildName`n")

$vcpkgDir = Join-Path (Join-Path $env:GITHUB_WORKSPACE 'vcpkg_installed') $env:VCPKG_TRIPLET
[System.IO.File]::AppendAllText($env:GITHUB_ENV, "VCPKG_DIR=$vcpkgDir`n")

$pythonDir = Join-Path (Join-Path $vcpkgDir 'tools') 'python3'
[System.IO.File]::AppendAllText($env:GITHUB_ENV, "PYTHON_DIR=$pythonDir`n")

$pythonExe = Join-Path $pythonDir 'python.exe'
[System.IO.File]::AppendAllText($env:GITHUB_ENV, "PYTHON=$pythonExe`n")

$updatedPath = "$pythonDir;$pythonDir\Scripts;$env:PATH"
[System.IO.File]::AppendAllText($env:GITHUB_ENV, "PATH=$updatedPath`n")
