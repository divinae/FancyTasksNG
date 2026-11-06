#!/bin/bash
# SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
# SPDX-License-Identifier: GPL-2.0-or-later

# Stop execution on error, treat unset variables as an error, catch pipe failures
set -Eeuo pipefail

# ANSI Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

# Error handler function
handle_error() {
    local line_num="$1"
    log_error "Script failed at line ${line_num}!"
}

# Set up global error trap
trap 'handle_error $LINENO' ERR

# Function to extract values from metadata.json
# Usage: get_metadata "Key" "PathToMetadata"
get_metadata() {
    local key="$1"
    local metadata_file="$2"
    
    if [ -z "$key" ] || [ ! -f "$metadata_file" ]; then
        return 1
    fi

    local val
    # 1. Try grep -P (fast and exact)
    # Using '|| true' because grep exits with 1 if nothing is found, which would trigger 'set -e'
    val=$(grep -oP "\"$key\"\s*:\s*\"\K[^\"]+" "$metadata_file" 2> /dev/null || true)

    # 2. If grep -P is not available, use sed (fallback)
    if [ -z "$val" ]; then
        val=$(grep "\"$key\":" "$metadata_file" | head -n 1 | sed -E 's/.*"'"$key"'"\s*:\s*"([^"]+)".*/\1/' || true)
    fi

    echo "$val"
}

# Patch the "Version" field of a metadata.json file in place.
# Usage: set_metadata_version <metadata_file> <new_version>
set_metadata_version() {
    local metadata_file="$1"
    local new_version="$2"
    sed -i -E 's/("Version"[[:space:]]*:[[:space:]]*")[^"]+(")/\1'"${new_version}"'\2/' "${metadata_file}"
}

# Compute the version to embed in a *built* package. The committed
# package/metadata.json is never touched between releases (see AGENTS.md's
# Release flow), so on any commit other than a release tag it would report a
# stale version - this resolves what to actually stamp on the built copy:
#   - not a git checkout at all (e.g. a source tarball)   -> committed version
#   - HEAD is exactly a release tag                       -> committed version
#   - otherwise                                            -> `git describe --tags`
#     (e.g. "2.1.0-12-gabc1234": last tag, commits ahead, short SHA), so a
#     build off any other commit traces back to exactly which one it's from.
# Usage: resolve_display_version <metadata_file>
resolve_display_version() {
    local metadata_file="$1"
    local base_version
    base_version=$(get_metadata "Version" "${metadata_file}")

    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        echo "${base_version}"
        return
    fi

    if git describe --tags --exact-match &> /dev/null; then
        echo "${base_version}"
        return
    fi

    local described
    if described=$(git describe --tags 2> /dev/null); then
        echo "${described#v}"
    else
        echo "${base_version}"
    fi
}
