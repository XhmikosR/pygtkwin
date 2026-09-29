#!/usr/bin/env bash
# Validate that the vcpkg build produced expected key files.
# Usage: ./validate-build.sh <vcpkg_installed_triplet_dir>
# Example: ./validate-build.sh vcpkg/installed/x86-windows
set -euo pipefail

dir="${1:?usage: $0 <triplet_dir>}"
bindir="$dir/bin"

if [ ! -d "$bindir" ]; then
    echo "ERROR: bin directory not found: $bindir" >&2
    exit 1
fi

errors=0

# Machine field of the PE header: 014c = x86, 8664 = x64
case "$(basename "$dir")" in
    x86-windows) bits=32 machine=014c ;;
    x64-windows) bits=64 machine=8664 ;;
    *)
        echo "ERROR: unknown triplet: $(basename "$dir")" >&2
        exit 1
        ;;
esac

# Sets file_machine for $1. e_lfanew at 0x3c points at the "PE\0\0" signature
# and the machine field follows it. One od per file, since forks are slow
# under Git Bash.
pe_machine() {
    local -a b
    local off
    file_machine=0000
    read -r -a b < <(od -An -v -tu1 -w1024 -N1024 "$1")
    [ "${#b[@]}" -ge 64 ] || return 0
    off=$(( b[60] | b[61] << 8 | b[62] << 16 | b[63] << 24 ))
    [ "$(( off + 5 ))" -lt "${#b[@]}" ] || return 0
    printf -v file_machine '%02x%02x' "${b[off + 5]}" "${b[off + 4]}"
}

check_glob() {
    local pattern="$1" label="$2" subdir="$3"
    local searchdir="$dir/$subdir"
    local found
    found=$(find "$searchdir" -name "$pattern" -type f 2>/dev/null || true)
    if [ -z "$found" ]; then
        echo "FAIL: $label not found (pattern: $pattern in $searchdir)"
        errors=$((errors + 1))
    else
        echo "OK:   $label -> ${found#$dir/}"
    fi
}

echo "=== Build validation: $bindir ==="

check_glob 'python.exe'           'python.exe'           'tools/python3'
check_glob 'gdbus.exe'            'gdbus.exe'            'tools/glib'
check_glob 'fc-cache.exe'         'fc-cache.exe'         'tools/fontconfig'
check_glob 'rsvg-*.dll'           'librsvg DLL'          'bin'
check_glob 'croco-*.dll'          'libcroco DLL'         'bin'
check_glob 'gdk_pixbuf-*.dll'     'gdk-pixbuf DLL'       'bin'
check_glob 'pixbufloader-svg.dll' 'pixbufloader-svg DLL' 'lib/gdk-pixbuf-2.0/2.10.0/loaders'
check_glob 'cairo*.dll'           'cairo DLL'            'bin'
check_glob 'glib-*.dll'           'glib DLL'             'bin'
check_glob 'libxml2.dll'          'libxml2 DLL'          'bin'
check_glob 'GLibWin32-2.0.typelib' 'GLibWin32 typelib'   'lib/girepository-1.0'
check_glob 'GioWin32-2.0.typelib'  'GioWin32 typelib'    'lib/girepository-1.0'
check_glob "gspawn-win$bits-helper.exe"         'gspawn helper'         'tools/glib'
check_glob "gspawn-win$bits-helper-console.exe" 'gspawn console helper' 'tools/glib'

# Lib/ is left out: pip ships launchers for every architecture there
for f in "$bindir"/*.dll "$dir"/tools/*/*.dll "$dir"/tools/*/*.exe \
         "$dir"/tools/python3/DLLs/*.pyd; do
    [ -f "$f" ] || continue
    pe_machine "$f"
    if [ "$file_machine" != "$machine" ]; then
        echo "FAIL: ${f#$dir/} has PE machine $file_machine, expected $machine"
        errors=$((errors + 1))
    fi
done

echo "=== Validation complete: $errors error(s) ==="

# Print debloat metrics: sizes of key DLLs and the bin directory total.
# Output is grep-friendly (key=value) so build logs can be diffed to track
# the effectiveness of the GTK/openssl debloat patches over time.
print_metric() {
    # $1 = metric name, $2 = file path (relative to $dir), $3 = absolute path
    local name="$1" rel="$2" f="$3"
    if [ -f "$f" ]; then
        local bytes human
        bytes=$(stat -c '%s' "$f")
        human=$(numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B")
        printf 'metric %s=%s bytes=%s file=%s\n' "$name" "$human" "$bytes" "$rel"
    else
        printf 'metric %s=MISSING file=%s\n' "$name" "$rel"
    fi
}

echo "=== Debloat metrics ==="
# gtk-3 DLL is the main GTK debloat target (e.g. gtk-3-vs17.dll).
gtk_dll=$(find "$bindir" -maxdepth 1 -name 'gtk-3-*.dll' -type f | head -n1)
print_metric 'gtk3_dll' "${gtk_dll#$dir/}" "$gtk_dll"
# openssl DLL is the openssl debloat target (0005-vcpkg-openssl-debloat.patch).
ssl_dll=$(find "$bindir" -maxdepth 1 -name 'libssl-3*.dll' -type f | head -n1)
print_metric 'openssl_dll' "${ssl_dll#$dir/}" "$ssl_dll"
# Secondary DLLs affected by the debloat configuration.
for name in 'librsvg-2-*.dll' 'libcroco-*.dll' 'gdk_pixbuf-*.dll' 'libgtk-3-*.dll'; do
    f=$(find "$bindir" -maxdepth 1 -name "$name" -type f | head -n1)
    [ -n "$f" ] && print_metric "$(basename "$f" .dll)" "${f#$dir/}" "$f"
done
# Total size of the bin directory (all shipped DLLs/exes).
bin_bytes=$(du -sb "$bindir" | cut -f1)
bin_human=$(numfmt --to=iec --suffix=B "$bin_bytes" 2>/dev/null || echo "${bin_bytes}B")
printf 'metric bin_total=%s bytes=%s\n' "$bin_human" "$bin_bytes"
echo "=== Debloat metrics end ==="

if [ "$errors" -gt 0 ]; then
    exit 1
fi
