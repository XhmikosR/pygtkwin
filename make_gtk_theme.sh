#!/usr/bin/env bash

set -euo pipefail

# Minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# Node and npm from setup-node on CI, the system ones otherwise
PATH="${NODE_DIR:+${NODE_DIR}:}${PATH}"

# Build gtk-themes.7z in the current directory. Run npm ci first for svgo.
# ASSET_CACHE_DIR, if set, keeps the optimized PNGs and SVGs between runs.

ADWAITA_VERSION=50.0
ADWAITA_SHA256=fac6e0401fca714780561a081b8f7e27c3bc1db34ebda4da175081f26b24d460
ADWAITA_URL="https://download.gnome.org/sources/adwaita-icon-theme/50/adwaita-icon-theme-${ADWAITA_VERSION}.tar.xz"

# Adwaita 47+ split legacy (fullcolor) icons into a separate package.
# The main index.theme inherits AdwaitaLegacy, so both are required.
ADWAITA_LEGACY_VERSION=46.2
ADWAITA_LEGACY_SHA256=548480f58589a54b72d18833b755b15ffbd567e3187249d74e2e1f8f99f22fb4
ADWAITA_LEGACY_URL="https://download.gnome.org/sources/adwaita-icon-theme-legacy/46/adwaita-icon-theme-legacy-${ADWAITA_LEGACY_VERSION}.tar.xz"

# hicolor is the ultimate fallback icon theme.
HICOLOR_VERSION=0.18
HICOLOR_SHA256=db0e50a80aa3bf64bb45cbca5cf9f75efd9348cf2ac690b907435238c3cf81d7
HICOLOR_URL="https://icon-theme.freedesktop.org/releases/hicolor-icon-theme-${HICOLOR_VERSION}.tar.xz"

GTK_VERSION=3.24.52
GTK_SHA256=80931fa472a77b9a164f6740e3c0b444fac6770054632d35a7ff9d679e5e7b9f
GTK_URL="https://download.gnome.org/sources/gtk/3.24/gtk-${GTK_VERSION}.tar.xz"

GNOME_THEMES_VERSION=3.28
GNOME_THEMES_SHA256=7c4ba0bff001f06d8983cfc105adaac42df1d1267a2591798a780bac557a5819
GNOME_THEMES_URL="https://download.gnome.org/sources/gnome-themes-extra/3.28/gnome-themes-extra-${GNOME_THEMES_VERSION}.tar.xz"

current_dir=$(pwd)
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cache_root=""
if [[ -n "${ASSET_CACHE_DIR:-}" ]]; then
    cache_root=$(realpath -m -- "${ASSET_CACHE_DIR}")
fi
work_dir=$(mktemp -d --suffix=gtktheme)
cd "${work_dir}"

download_and_extract() {
    local url="$1" sha256="$2"
    local filename="${url##*/}"

    if ! curl -fsSL "${url}" -o "${filename}"; then
        echo "Failed to download ${filename}"
        exit 1
    fi

    echo "${sha256}  ${filename}" | sha256sum -c -
    tar -xf "${filename}"
    rm -f -- "${filename}"
}

download_and_extract "${ADWAITA_URL}" "${ADWAITA_SHA256}"
mkdir -p gtk-themes/share/icons
mv adwaita-icon-theme-${ADWAITA_VERSION}/Adwaita gtk-themes/share/icons
cp adwaita-icon-theme-${ADWAITA_VERSION}/index.theme gtk-themes/share/icons/Adwaita/index.theme

download_and_extract "${ADWAITA_LEGACY_URL}" "${ADWAITA_LEGACY_SHA256}"
mv adwaita-icon-theme-legacy-${ADWAITA_LEGACY_VERSION}/AdwaitaLegacy gtk-themes/share/icons
cp adwaita-icon-theme-legacy-${ADWAITA_LEGACY_VERSION}/index.theme gtk-themes/share/icons/AdwaitaLegacy/index.theme

download_and_extract "${HICOLOR_URL}" "${HICOLOR_SHA256}"
mkdir -p gtk-themes/share/icons/hicolor
cp hicolor-icon-theme-${HICOLOR_VERSION}/index.theme gtk-themes/share/icons/hicolor/index.theme

download_and_extract "${GTK_URL}" "${GTK_SHA256}"
cd "gtk-${GTK_VERSION}/gtk/theme/Adwaita"
./parse-sass.sh
if [[ ! -f gtk-contained.css ]]; then
    echo "Error: gtk-contained.css not found"
    exit 1
fi

cd "${work_dir}"
mkdir -p gtk-themes/share/themes/Adwaita/gtk-3.0
mv "gtk-${GTK_VERSION}/gtk/theme/Adwaita/gtk-contained.css" "gtk-themes/share/themes/Adwaita/gtk-3.0/gtk.css"
cp "gtk-${GTK_VERSION}/gtk/theme/Adwaita/gtk-contained-dark.css" "gtk-themes/share/themes/Adwaita/gtk-3.0/gtk-dark.css"
cp -r "gtk-${GTK_VERSION}/gtk/theme/Adwaita/assets" "gtk-themes/share/themes/Adwaita/gtk-3.0/assets"

# GTK expects a theme index.theme; BleachBit's installer also checks for it.
cat > gtk-themes/share/themes/Adwaita/index.theme << 'EOF'
[X-GNOME-Metatheme]
Name=Adwaita
Type=X-GNOME-Metatheme
Comment=There is only one
Encoding=UTF-8
GtkTheme=Adwaita
MetacityTheme=Adwaita
IconTheme=Adwaita
CursorTheme=Adwaita
CursorSize=24
EOF

download_and_extract "${GNOME_THEMES_URL}" "${GNOME_THEMES_SHA256}"
mkdir -p gtk-themes/share/icons/HighContrast
rm -f -- "gnome-themes-extra-${GNOME_THEMES_VERSION}/themes/HighContrast/icons/scalable/Makefile.am"
mv "gnome-themes-extra-${GNOME_THEMES_VERSION}/themes/HighContrast/icons/scalable" "gtk-themes/share/icons/HighContrast"
cp "gnome-themes-extra-${GNOME_THEMES_VERSION}/themes/HighContrast/icons/index.theme" "gtk-themes/share/icons/HighContrast/index.theme"

# Optimize PNG and SVG assets to shrink the final archive.
# oxipng losslessly recompresses PNGs; svgo strips redundancy from SVGs.
# Both run in place. They are timed and the total size delta is printed so
# the size/time tradeoff is visible in the build log.
if ! command -v oxipng > /dev/null 2>&1; then
    echo "Error: oxipng not found; install it to optimize PNGs"
    exit 1
fi
if ! command -v npm > /dev/null 2>&1; then
    echo "Error: npm not found; it runs svgo to optimize SVGs"
    exit 1
fi

oxipng_args=(--opt max --alpha --fix -s --preserve)
# The Zopfli option is much slower but further shrinks the images
oxipng_zopfli_args=(--opt max --alpha --fix --preserve -z --fast)
svgo_args=(--multipass --quiet)
svgo=(npm --prefix "${repo_dir}" run --silent svgo --)

# Sum of byte sizes of all regular files under $1 matching name glob $2.
total_bytes() {
    find "$1" -type f -name "$2" -printf '%s\n' | awk '{s+=$1} END {print s+0}'
}

# Sum of byte sizes of the files in the NUL-separated list $1
list_bytes() {
    xargs -0 -r stat -c '%s' < "$1" | awk '{s+=$1} END {print s+0}'
}

# Print "label: before -> after bytes (saved, pct%)".
print_savings() {
    local label="$1" before="$2" after="$3" saved pct
    saved=$(("${before}" - "${after}"))
    if [[ "${before}" -gt 0 ]]; then
        pct=$(awk -v s="${saved}" -v b="${before}" 'BEGIN{printf "%.2f", s*100/b}')
    else
        pct="0.00"
    fi
    echo "${label}: ${before} -> ${after} bytes (${saved} saved, ${pct}%)"
}

# Both take a NUL-separated file list
optimize_pngs() {
    local list="$1" before after

    # Without Zopfli option, oxipng runs quickly.
    echo "==> Optimizing PNG files with oxipng"
    before=$(list_bytes "${list}")
    time xargs -0 -r oxipng "${oxipng_args[@]}" < "${list}"
    after=$(list_bytes "${list}")
    print_savings "PNG" "${before}" "${after}"

    echo "==> Re-compressing PNGs with oxipng Zopfli (-z --fast)"
    before="${after}"
    time xargs -0 -r oxipng "${oxipng_zopfli_args[@]}" < "${list}"
    after=$(list_bytes "${list}")
    print_savings "PNG (zopfli)" "${before}" "${after}"
}

optimize_svgs() {
    local list="$1" before after

    echo "==> Optimizing SVG files with svgo"
    before=$(list_bytes "${list}")
    # npm hands the whole command to sh as one argument, capped at 128 KiB
    time xargs -0 -r -n 500 "${svgo[@]}" "${svgo_args[@]}" < "${list}"
    after=$(list_bytes "${list}")
    print_savings "SVG" "${before}" "${after}"
}

# Neither oxipng nor svgo can skip already optimized files, so results are
# cached by input hash. Only the entries this run uses move over from the
# previous cache, which drops stale ones.
if [[ -n "${cache_root}" ]]; then
    rm -rf -- "${cache_root}.old"
    if [[ -d "${cache_root}" ]]; then
        mv -- "${cache_root}" "${cache_root}.old"
    fi
    mkdir -p -- "${cache_root}"
fi

# optimize_cached <label> <name glob> <cache key> <optimize function>
# The key holds the tool version and flags, so output from other settings is
# never reused.
optimize_cached() {
    local label="$1" pattern="$2" key="$3" optimize="$4"
    local list="${work_dir}/${label}.list" map="${work_dir}/${label}.map"
    local ns="" old="" hash file hits=0 misses=0 before after
    : > "${list}"
    : > "${map}"

    if [[ -n "${cache_root}" ]]; then
        ns="${label}-$(printf '%s' "${key}" | sha256sum | cut -c1-16)"
        old="${cache_root}.old/${ns}"
        ns="${cache_root}/${ns}"
        mkdir -p -- "${ns}"
    fi

    before=$(total_bytes gtk-themes "${pattern}")
    while read -r hash file; do
        if [[ -n "${ns}" && -f "${ns}/${hash}" ]]; then
            cp -p -- "${ns}/${hash}" "${file}"
            hits=$((hits + 1))
        elif [[ -n "${ns}" && -f "${old}/${hash}" ]]; then
            mv -- "${old}/${hash}" "${ns}/${hash}"
            cp -p -- "${ns}/${hash}" "${file}"
            hits=$((hits + 1))
        else
            printf '%s\0' "${file}" >> "${list}"
            printf '%s %s\n' "${hash}" "${file}" >> "${map}"
            misses=$((misses + 1))
        fi
    done < <(find "${work_dir}/gtk-themes" -type f -name "${pattern}" -print0 | xargs -0 -r sha256sum)
    echo "==> ${label}: ${hits} cached, ${misses} to optimize"

    if [[ "${misses}" -gt 0 ]]; then
        "${optimize}" "${list}"
    fi

    if [[ -n "${ns}" ]]; then
        while read -r hash file; do
            cp -p -- "${file}" "${ns}/${hash}"
        done < "${map}"
    fi
    after=$(total_bytes gtk-themes "${pattern}")
    print_savings "${label} total" "${before}" "${after}"
}

optimize_cached PNG '*.png' \
    "$(oxipng --version) ${oxipng_args[*]} ${oxipng_zopfli_args[*]}" optimize_pngs
optimize_cached SVG '*.svg' \
    "$("${svgo[@]}" --version) ${svgo_args[*]}" optimize_svgs

if [[ -n "${cache_root}" ]]; then
    rm -rf -- "${cache_root}.old"
fi

7z a -t7z -m0=LZMA2 -mx=9 -mmt=on "${current_dir}/gtk-themes.7z" gtk-themes
du -b "${current_dir}/gtk-themes.7z"
sha256sum "${current_dir}/gtk-themes.7z"
