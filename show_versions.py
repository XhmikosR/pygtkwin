import os
import sys
import platform
import getopt
import ctypes
import ctypes.util
from ctypes import wintypes


def print_gi_versions():
    """Print versions of GTK, Pango, etc."""
    gi = None
    try:
        import gi as _gi
    except ImportError as e:
        print(f"PyGObject not available: {e} --- This is normal before building it.")
    else:
        gi = _gi
        print(f"PyGObject version: {gi.__version__}")

    if gi is None:
        return

    try:
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
    except (ImportError, ValueError) as e:
        print(f"GTK not available: {e}")
    else:
        print(f"Gtk version: {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}")

    try:
        gi.require_version("Pango", "1.0")
        from gi.repository import Pango
        print(f"Pango version: {Pango.version_string()}")
    except (ImportError, ValueError) as e:
        print(f"Pango not available: {e}")


def print_versions():
    """Print versions of Python, GTK, etc."""
    print(f"Machine: {platform.machine()}")
    print(f"Python version: {sys.version}")
    print(f"Python bitness: {platform.architecture()[0]}")
    print(f"Python compiler: {platform.python_compiler()}")
    print_gi_versions()

    fontconfig_version = _get_fontconfig_version()
    if fontconfig_version:
        print(f"Fontconfig version: {fontconfig_version}")
    else:
        print("Fontconfig version: unavailable")

    harfbuzz_version = _get_harfbuzz_version()
    if harfbuzz_version:
        print(f"HarfBuzz version: {harfbuzz_version}")
    else:
        print("HarfBuzz version: unavailable")

    try:
        vcruntime_dll = ctypes.WinDLL("vcruntime140.dll")
    except OSError:
        print("vcruntime140.dll not available")
    else:
        vcruntime_version = get_file_version(vcruntime_dll._name)
        if vcruntime_version:
            print(f"vcruntime140.dll version: {'.'.join(map(str, vcruntime_version))}")
        else:
            print("vcruntime140.dll version: unavailable")


def _get_fontconfig_version():
    """Get the version of fontconfig"""
    libname = ctypes.util.find_library("fontconfig-1") or "fontconfig-1"
    try:
        lib = ctypes.CDLL(libname)
        lib.FcGetVersion.restype = ctypes.c_int
        version = lib.FcGetVersion()
        major = version // 10000
        minor = (version % 10000) // 100
        micro = version % 100
        return f"{major}.{minor}.{micro}"
    except (OSError, AttributeError, ValueError):
        return None


def _get_harfbuzz_version():
    """Get the version of harfbuzz"""
    libname = ctypes.util.find_library("harfbuzz") or "harfbuzz"
    try:
        lib = ctypes.CDLL(libname)
        lib.hb_version_string.restype = ctypes.c_char_p
        version = lib.hb_version_string()
        if version:
            return version.decode()
    except (OSError, AttributeError, ValueError):
        return None
    return None


def get_file_version(path):
    """Get the version of a file"""
    path = str(path)
    size = ctypes.windll.version.GetFileVersionInfoSizeW(path, None)
    if not size:
        return None
    res = ctypes.create_string_buffer(size)
    ctypes.windll.version.GetFileVersionInfoW(path, 0, size, res)
    lptr = ctypes.c_void_p()
    lsize = wintypes.UINT()
    ctypes.windll.version.VerQueryValueW(res, "\\", ctypes.byref(lptr), ctypes.byref(lsize))
    if not lsize:
        return None

    vs_fixed = ctypes.cast(lptr, ctypes.POINTER(ctypes.c_uint32 * (lsize.value // 4))).contents
    # VS_FIXEDFILEINFO starts with the signature and the struct version
    ms = vs_fixed[2]
    ls = vs_fixed[3]
    return ((ms >> 16) & 0xFFFF, ms & 0xFFFF, (ls >> 16) & 0xFFFF, ls & 0xFFFF)


def main():
    """Main entry point"""
    if os.name != "nt":
        print("This script is only for Windows")
        sys.exit(1)

    try:
        opts, _args = getopt.getopt(sys.argv[1:], "hd:", ["help", "dll-directory="])
    except getopt.GetoptError as err:
        print(str(err))
        sys.exit(2)

    for opt, arg in opts:
        if opt in ("-h", "--help"):
            print(f"Usage: {os.path.basename(sys.argv[0])} [--dll-directory=DIR]")
            sys.exit()
        elif opt in ("-d", "--dll-directory"):
            os.add_dll_directory(arg)

    print("Environment PATH:")
    print(os.environ['PATH'].split(os.pathsep))
    print("\nPython module search path:")
    print(sys.path)

    print_versions()


if __name__ == "__main__":
    main()
