#!/usr/bin/env bash

# shellcheck enable=require-variable-braces

set -euo pipefail

# Minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# Node and npm from setup-node on CI, the system ones otherwise
PATH="${NODE_DIR:+${NODE_DIR}:}${PATH}"

# Build gtk-themes.7z in the current directory. Run npm ci first for svgo.

current_dir=$(pwd)
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work_dir=$(mktemp -d --suffix=gtktheme)
cd "${work_dir}"

download_and_extract() {
    local url="$1" sha256="$2"
    local filename="${url##*/}"

    curl -fsSL "${url}" -o "${filename}" || { echo "Failed to download ${filename}"; exit 1; }
    echo "${sha256}  ${filename}" | sha256sum -c -
    tar -xf "${filename}"
    rm -f -- "${filename}"
}

ADAWAITA_VERSION=50.0
ADAWAITA_SHA256=fac6e0401fca714780561a081b8f7e27c3bc1db34ebda4da175081f26b24d460
ADAWAITA_URL="https://download.gnome.org/sources/adwaita-icon-theme/50/adwaita-icon-theme-${ADAWAITA_VERSION}.tar.xz"
download_and_extract "${ADAWAITA_URL}" "${ADAWAITA_SHA256}"
mkdir -p gtk-themes/share/icons
mv adwaita-icon-theme-${ADAWAITA_VERSION}/Adwaita gtk-themes/share/icons
cp adwaita-icon-theme-${ADAWAITA_VERSION}/index.theme gtk-themes/share/icons/Adwaita/index.theme

# Adwaita 47+ split legacy (fullcolor) icons into a separate package.
# The main index.theme inherits AdwaitaLegacy, so both are required.
ADAWAITA_LEGACY_VERSION=46.2
ADAWAITA_LEGACY_SHA256=548480f58589a54b72d18833b755b15ffbd567e3187249d74e2e1f8f99f22fb4
ADAWAITA_LEGACY_URL="https://download.gnome.org/sources/adwaita-icon-theme-legacy/46/adwaita-icon-theme-legacy-${ADAWAITA_LEGACY_VERSION}.tar.xz"
download_and_extract "${ADAWAITA_LEGACY_URL}" "${ADAWAITA_LEGACY_SHA256}"
mv adwaita-icon-theme-legacy-${ADAWAITA_LEGACY_VERSION}/AdwaitaLegacy gtk-themes/share/icons
cp adwaita-icon-theme-legacy-${ADAWAITA_LEGACY_VERSION}/index.theme gtk-themes/share/icons/AdwaitaLegacy/index.theme

# hicolor is the ultimate fallback icon theme.
HICOLOR_VERSION=0.18
HICOLOR_SHA256=db0e50a80aa3bf64bb45cbca5cf9f75efd9348cf2ac690b907435238c3cf81d7
HICOLOR_URL="https://icon-theme.freedesktop.org/releases/hicolor-icon-theme-${HICOLOR_VERSION}.tar.xz"
download_and_extract "${HICOLOR_URL}" "${HICOLOR_SHA256}"
mkdir -p gtk-themes/share/icons/hicolor
cp hicolor-icon-theme-${HICOLOR_VERSION}/index.theme gtk-themes/share/icons/hicolor/index.theme

GTK_VER=3.24.52
GTK_SHA256=80931fa472a77b9a164f6740e3c0b444fac6770054632d35a7ff9d679e5e7b9f
GTK_URL="https://download.gnome.org/sources/gtk/3.24/gtk-${GTK_VER}.tar.xz"
download_and_extract "${GTK_URL}" "${GTK_SHA256}"
cd "gtk-${GTK_VER}/gtk/theme/Adwaita" || { echo "Failed to cd into Adwaita"; exit 1; }
./parse-sass.sh
if [ ! -f gtk-contained.css ]; then
    echo "Error: gtk-contained.css not found"
    exit 1
fi

cd "${work_dir}"
mkdir -p gtk-themes/share/themes/Adwaita/gtk-3.0
mv "gtk-${GTK_VER}/gtk/theme/Adwaita/gtk-contained.css" "gtk-themes/share/themes/Adwaita/gtk-3.0/gtk.css"
cp "gtk-${GTK_VER}/gtk/theme/Adwaita/gtk-contained-dark.css" "gtk-themes/share/themes/Adwaita/gtk-3.0/gtk-dark.css"
cp -r "gtk-${GTK_VER}/gtk/theme/Adwaita/assets" "gtk-themes/share/themes/Adwaita/gtk-3.0/assets"

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

GNOME_THEMES_VER=3.28
GNOME_THEMES_SHA256=7c4ba0bff001f06d8983cfc105adaac42df1d1267a2591798a780bac557a5819
GTKTHEMES_URL="https://download.gnome.org/sources/gnome-themes-extra/3.28/gnome-themes-extra-${GNOME_THEMES_VER}.tar.xz"
download_and_extract "${GTKTHEMES_URL}" "${GNOME_THEMES_SHA256}"
mkdir -p gtk-themes/share/icons/HighContrast
rm -f -- "gnome-themes-extra-${GNOME_THEMES_VER}/themes/HighContrast/icons/scalable/Makefile.am"
mv "gnome-themes-extra-${GNOME_THEMES_VER}/themes/HighContrast/icons/scalable" "gtk-themes/share/icons/HighContrast"
cp "gnome-themes-extra-${GNOME_THEMES_VER}/themes/HighContrast/icons/index.theme" "gtk-themes/share/icons/HighContrast/index.theme"

# Optimize PNG and SVG assets to shrink the final archive.
# oxipng losslessly recompresses PNGs; svgo strips redundancy from SVGs.
# Both run in place. They are timed and the total size delta is printed so
# the size/time tradeoff is visible in the build log.
command -v oxipng >/dev/null 2>&1 || { echo "Error: oxipng not found; install it to optimize PNGs"; exit 1; }
command -v npm    >/dev/null 2>&1 || { echo "Error: npm not found; it runs svgo to optimize SVGs"; exit 1; }

# Sum of byte sizes of all regular files under $1 matching name glob $2.
total_bytes() {
    find "$1" -type f -name "$2" -printf '%s\n' | awk '{s+=$1} END {print s+0}'
}

# Print "label: before -> after bytes (saved, pct%)".
print_savings() {
    local label="$1" before="$2" after="$3" saved pct
    saved=$(( "${before}" - "${after}" ))
    if [ "${before}" -gt 0 ]; then
        pct=$(awk -v s="${saved}" -v b="${before}" 'BEGIN{printf "%.2f", s*100/b}')
    else
        pct="0.00"
    fi
    echo "${label}: ${before} -> ${after} bytes (${saved} saved, ${pct}%)"
}

# Without Zopfli option, oxipng runs quickly.
echo "==> Optimizing PNG files with oxipng"
png_before=$(total_bytes gtk-themes '*.png')
time oxipng --opt max --alpha --fix -s --preserve -r gtk-themes
png_after=$(total_bytes gtk-themes '*.png')
print_savings "PNG" "${png_before}" "${png_after}"

# The oxipng Zopfli option is much slower but further shrinks the images.
echo "==> Re-compressing PNGs with oxipng Zopfli (-z --fast)"
png_zopfli_before=$(total_bytes gtk-themes '*.png')
time oxipng --opt max --alpha --fix --preserve -z --fast -r gtk-themes
png_zopfli_after=$(total_bytes gtk-themes '*.png')
print_savings "PNG (zopfli)" "${png_zopfli_before}" "${png_zopfli_after}"

echo "==> Optimizing SVG files with svgo"
svg_before=$(total_bytes gtk-themes '*.svg')
# npm hands the whole command to sh as one argument, capped at 128 KiB
time find "${work_dir}/gtk-themes" -type f -name '*.svg' -print0 \
    | xargs -r -0 -n 500 npm --prefix "${repo_dir}" run --silent svgo -- --multipass --quiet
svg_after=$(total_bytes gtk-themes '*.svg')
print_savings "SVG" "${svg_before}" "${svg_after}"

7za a -t7z -mx=9 -mmt=on "${current_dir}/gtk-themes.7z" gtk-themes
du -b "${current_dir}/gtk-themes.7z"
sha256sum "${current_dir}/gtk-themes.7z"
