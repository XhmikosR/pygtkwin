#!/usr/bin/env bash

set -euo pipefail

# Minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Install the tools make_gtk_theme.sh needs on an Ubuntu runner. svgo comes
# from npm ci.

OXIPNG_VERSION=10.2.1
OXIPNG_SHA256=46e3c4beb9aae57290ad809dd3374b07153579d3322a3778c53900633618b7c6

# Remove the Microsoft package repo: it intermittently returns
# 403 Forbidden on apt-get update, and none of these packages use it.
sudo rm -f /etc/apt/sources.list.d/*microsoft*
sudo apt-get update
sudo apt-get install -y --no-install-recommends sassc

tmp_dir=$(mktemp -d)
trap 'rm -rf -- "${tmp_dir}"' EXIT

oxipng_name="oxipng-${OXIPNG_VERSION}-x86_64-unknown-linux-gnu"
curl -fsSL --retry 3 "https://github.com/oxipng/oxipng/releases/download/v${OXIPNG_VERSION}/${oxipng_name}.tar.gz" -o "${tmp_dir}/oxipng.tar.gz"
echo "${OXIPNG_SHA256}  ${tmp_dir}/oxipng.tar.gz" | sha256sum -c -
tar -xzf "${tmp_dir}/oxipng.tar.gz" -C "${tmp_dir}"
sudo install -m 0755 "${tmp_dir}/${oxipng_name}/oxipng" /usr/local/bin/oxipng
oxipng --version
