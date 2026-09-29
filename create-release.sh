#!/usr/bin/env bash

# shellcheck enable=require-variable-braces

set -euo pipefail

# Minimal PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Create the release for a tag with the given files, or add them to it if it
# already exists. The PyGTK and themes workflows publish to the same release.
# Needs GH_TOKEN and GH_REPO.
# Usage: ./create-release.sh <tag> <file>...

usage="usage: $0 <tag> <file>..."
tag="${1:?${usage}}"
shift
[ "$#" -gt 0 ] || { echo "${usage}" >&2; exit 1; }

if ! gh release view "${tag}" > /dev/null 2>&1; then
    # The other workflow can still create it first, then upload below
    if gh release create "${tag}" --verify-tag --generate-notes "$@"; then
        exit 0
    fi
fi
gh release upload "${tag}" --clobber "$@"
