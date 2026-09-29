# GTK and Python for Windows

This project builds the Python and GTK framework for BleachBit
to use on Microsoft Windows. This includes introspection support
and a PyGObject wheel. Consistent with PyPI packaging practices, we
use Microsoft Visual C++ and vcpkg instead of gcc and MSYS2.

Each release has a 32-bit (`x86-windows`) and a 64-bit (`x64-windows`)
build, each with its own PyGObject wheel.

As of 2026-09-09, this project builds:

* Python 3.12.13
* GTK 3.24.52
* PyGObject 3.58.0
* Cairo 1.18.4
* Pango 1.58.0
* Fontconfig 2.17.1
* HarfBuzz 14.4.0

The build environment is GitHub Actions with MSVC++ 2022.
For more information about the build environment and build
process, see the [GitHub Action YAML files](https://github.com/bleachbit/pygtkwin/tree/main/.github/workflows)
or [logs](https://github.com/bleachbit/pygtkwin/actions).

Perhaps you are looking for a PyGTK all in one (AIO) installer,
but the others you found were years out of date? If you need to
run GTK on Windows, try this repository plus the
[install script](https://github.com/bleachbit/bleachbit/blob/master/windows/python-gtk3-install.ps1)
from the BleachBit repository.

Copyright (C) 2025 to 2026 by Andrew Ziem. All rights reserved.
See [LICENSE](LICENSE) for license information.

Special thanks to @soylent-io and @soreau for their work to keep BleachBit
running on Windows.

Tip: [nektos/act](https://github.com/nektos/act) is tool for running GitHub Actions locally.

## Viewing run status and logs

Use the [GitHub CLI (`gh`)](https://github.com/cli/cli/).

List recent runs:

```console
$ gh run list
STATUS  TITLE                              WORKFLOW                 BRANCH  EVENT  ID           ELAPSED  AGE
✓       Restore vcpkg install for libcroso  Build GTK themes         dev     push   29065380640  1m3s     about 11 hours ago
X       Restore vcpkg install for libcroso  Build and Package PyGTK  dev     push   29065380636  11m15s   about 11 hours ago
```

View the log for a specific run. Recent versions of `gh` stream the log
directly without downloading it first; if the command fails, upgrade `gh`.

```bash
gh run view 29065380636 --log
```
