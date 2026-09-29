#!/bin/bash

# shellcheck enable=require-variable-braces

set -euo pipefail

current_dir=$(pwd)
work_dir=$(mktemp -d --suffix=gtktheme)
cd "${work_dir}"

download_and_extract() {
    local url="$1"
    local filename="${url##*/}"

    wget -q "${url}" -O "${filename}" || { echo "Failed to download ${filename}"; exit 1; }
    sha256sum "${filename}"
    tar -xf "${filename}"
    rm -f -- "${filename}"
}

ADAWAITA_VERSION=50.0
ADAWAITA_URL="https://download.gnome.org/sources/adwaita-icon-theme/50/adwaita-icon-theme-${ADAWAITA_VERSION}.tar.xz"
download_and_extract "${ADAWAITA_URL}"
mkdir -p gtk-themes/share/icons
mv adwaita-icon-theme-${ADAWAITA_VERSION}/Adwaita gtk-themes/share/icons
cp adwaita-icon-theme-${ADAWAITA_VERSION}/index.theme gtk-themes/share/icons/Adwaita/index.theme

# Adwaita 47+ split legacy (fullcolor) icons into a separate package.
# The main index.theme inherits AdwaitaLegacy, so both are required.
ADAWAITA_LEGACY_VERSION=46.2
ADAWAITA_LEGACY_URL="https://download.gnome.org/sources/adwaita-icon-theme-legacy/46/adwaita-icon-theme-legacy-${ADAWAITA_LEGACY_VERSION}.tar.xz"
download_and_extract "${ADAWAITA_LEGACY_URL}"
mv adwaita-icon-theme-legacy-${ADAWAITA_LEGACY_VERSION}/AdwaitaLegacy gtk-themes/share/icons
cp adwaita-icon-theme-legacy-${ADAWAITA_LEGACY_VERSION}/index.theme gtk-themes/share/icons/AdwaitaLegacy/index.theme

# hicolor is the ultimate fallback icon theme.
HICOLOR_VERSION=0.18
HICOLOR_URL="https://icon-theme.freedesktop.org/releases/hicolor-icon-theme-${HICOLOR_VERSION}.tar.xz"
download_and_extract "${HICOLOR_URL}"
mkdir -p gtk-themes/share/icons/hicolor
cp hicolor-icon-theme-${HICOLOR_VERSION}/index.theme gtk-themes/share/icons/hicolor/index.theme

GTK_VER=3.24.52
GTK_URL="https://download.gnome.org/sources/gtk/3.24/gtk-${GTK_VER}.tar.xz"
download_and_extract "${GTK_URL}"
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
GTKTHEMES_URL="https://download.gnome.org/sources/gnome-themes-extra/3.28/gnome-themes-extra-${GNOME_THEMES_VER}.tar.xz"
download_and_extract "${GTKTHEMES_URL}"
mkdir -p gtk-themes/share/icons/HighContrast
rm -f -- "gnome-themes-extra-${GNOME_THEMES_VER}/themes/HighContrast/icons/scalable/Makefile.am"
mv "gnome-themes-extra-${GNOME_THEMES_VER}/themes/HighContrast/icons/scalable" "gtk-themes/share/icons/HighContrast"
cp "gnome-themes-extra-${GNOME_THEMES_VER}/themes/HighContrast/icons/index.theme" "gtk-themes/share/icons/HighContrast/index.theme"

# Optimize PNG and SVG assets to shrink the final archive.
# oxipng losslessly recompresses PNGs; svgo strips redundancy from SVGs.
# Both run in place. They are timed and the total size delta is printed so
# the size/time tradeoff is visible in the build log.
command -v oxipng >/dev/null 2>&1 || { echo "Error: oxipng not found; install it to optimize PNGs"; exit 1; }
command -v svgo   >/dev/null 2>&1 || { echo "Error: svgo not found; install it to optimize SVGs"; exit 1; }

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
time oxipng --opt max --strip safe --alpha --fix --preserve -r gtk-themes
png_after=$(total_bytes gtk-themes '*.png')
print_savings "PNG" "${png_before}" "${png_after}"

# The oxipng Zopfli option is much slower but further shrinks the images.
echo "==> Re-compressing PNGs with oxipng Zopfli (-z --fast)"
png_zopfli_before=$(total_bytes gtk-themes '*.png')
time oxipng --opt max --strip safe --alpha --fix --preserve -z --fast -r gtk-themes
png_zopfli_after=$(total_bytes gtk-themes '*.png')
print_savings "PNG (zopfli)" "${png_zopfli_before}" "${png_zopfli_after}"

echo "==> Optimizing SVG files with svgo"
svg_before=$(total_bytes gtk-themes '*.svg')
time find gtk-themes -type f -name '*.svg' -print0 \
    | xargs -r -0 svgo --multipass --quiet
svg_after=$(total_bytes gtk-themes '*.svg')
print_savings "SVG" "${svg_before}" "${svg_after}"

7za a -t7z -mx=9 -mmt=on "${current_dir}/gtk-themes.7z" gtk-themes
du -b "${current_dir}/gtk-themes.7z"
sha256sum "${current_dir}/gtk-themes.7z"
