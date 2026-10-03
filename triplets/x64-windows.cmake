set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_BUILD_TYPE release)

# libtool's dumpbin export list and CMake's WINDOWS_EXPORT_ALL_SYMBOLS can't
# read /GL objects, so the ports that rely on them build without LTCG
if(NOT PORT MATCHES "^(gettext|gettext-libintl|getopt-win32|gperf|libcroco|libffi|libiconv)$")
    set(VCPKG_C_FLAGS "/GL")
    set(VCPKG_CXX_FLAGS "/GL")
    set(VCPKG_LINKER_FLAGS "/LTCG")
endif()
string(APPEND VCPKG_LINKER_FLAGS " /RELEASE /OPT:REF")

# ICF merges functions that CPython's typeobject.c tells apart by address,
# so python3 keeps the /OPT:NOICF that CPython links with
if(PORT STREQUAL "python3")
    string(APPEND VCPKG_LINKER_FLAGS " /OPT:NOICF")
else()
    string(APPEND VCPKG_LINKER_FLAGS " /OPT:ICF")
endif()
