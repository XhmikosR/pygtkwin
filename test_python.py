"""Check the built Python for known miscompilations and missing DLLs."""

import importlib
import os
import sys


class List(list):
    pass


def check_icf():
    # Linked with /OPT:ICF, this ran list concatenation on the int and
    # crashed instead of raising TypeError
    try:
        _ = 1 + List()
    except TypeError:
        return
    sys.exit("1 + List() did not raise TypeError")


def check_extensions():
    # Each module needs its DLLs next to it, like libmpdec for _decimal
    dlls = os.path.join(sys.base_prefix, "DLLs")
    modules = [name[:-4] for name in sorted(os.listdir(dlls)) if name.endswith(".pyd")]
    for module in modules:
        importlib.import_module(module)
    print(f"Imported {len(modules)} extension modules")


def main():
    check_icf()
    check_extensions()


if __name__ == "__main__":
    main()
