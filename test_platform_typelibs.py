"""Check that PyGObject loads the GLibWin32 and GioWin32 platform typelibs.

Run with GI_TYPELIB_PATH pointing at the build's girepository-1.0, e.g.:

    python test_platform_typelibs.py --dll-directory <vcpkg_installed>/x86-windows/bin

GLib only warns on stderr about missing or conflicting platform typelibs, so
the caller has to check stderr as well as the exit code.
"""

import getopt
import os
import sys


def main():
    try:
        opts, _args = getopt.getopt(sys.argv[1:], "hd:", ["help", "dll-directory="])
    except getopt.GetoptError as err:
        print(err, file=sys.stderr)
        sys.exit(2)

    for opt, arg in opts:
        if opt in ("-h", "--help"):
            print(f"Usage: {os.path.basename(sys.argv[0])} [--dll-directory=DIR]")
            sys.exit(0)
        elif opt in ("-d", "--dll-directory"):
            os.add_dll_directory(os.path.abspath(arg))

    # Imported after os.add_dll_directory so the GTK DLLs are found
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gio, GioWin32, GLibWin32, Gtk  # noqa: F401

    missing = []
    if not hasattr(GLibWin32, "get_command_line"):
        missing.append("GLibWin32.get_command_line")
    for cls in (GioWin32.InputStream, GioWin32.OutputStream):
        if not hasattr(cls, "get_handle"):
            missing.append(f"GioWin32.{cls.__name__}.get_handle")
    if missing:
        print(f"FAIL: missing {', '.join(missing)}")
        sys.exit(1)
    print("PASS: GLibWin32 and GioWin32 typelibs loaded")


if __name__ == "__main__":
    main()
