#!/bin/bash
# SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
# SPDX-FileCopyrightText: 2022-2023 Alexandra <alexankitty@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "${SCRIPT_DIR}/functions.sh"

PACKAGE_DIR="$(readlink -f "${SCRIPT_DIR}/../package")"

log_info "1. Syncing cfg_*Default values with main.xml..."
python3 "${SCRIPT_DIR}/sync_defaults.py"

log_info "2. Starting plasmawindowed from local source..."

export QT_LOGGING_RULES="kf.*=false;org.kde.*=false"
export QML_DISABLE_DISK_CACHE="true"

plasmawindowed "${PACKAGE_DIR}"
