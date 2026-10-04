set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_BUILD_TYPE release)

set(VCPKG_LINKER_FLAGS "/RELEASE /OPT:REF")

# ICF merges functions that CPython's typeobject.c tells apart by address,
# so python3 keeps the /OPT:NOICF that CPython links with
if(PORT STREQUAL "python3")
    string(APPEND VCPKG_LINKER_FLAGS " /OPT:NOICF")
else()
    string(APPEND VCPKG_LINKER_FLAGS " /OPT:ICF")
endif()
