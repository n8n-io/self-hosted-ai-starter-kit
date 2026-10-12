#!/usr/bin/env bash

###
# Shared utility functions for bash scripts
# Usage: source this file in your scripts
#   source "$(dirname "$0")/utils.sh"
###

# ============================================================================
# Exit Codes
# ============================================================================

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# ============================================================================
# Logging Functions
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BRIGHT_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Usage: log_info "message" ["custom_prefix"]
log_info() {
    local prefix="${2:-INFO}"
    echo -e "${GREEN}[${prefix}]${NC} $1"
}

# Usage: log_success "message" ["custom_prefix"]
log_success() {
    local prefix="${2:-SUCCESS}"
    echo -e "${BRIGHT_GREEN}[${prefix}]${NC} $1"
}

# Usage: log_skip "message" ["custom_prefix"]
log_skip() {
    local prefix="${2:-SKIP}"
    echo -e "${CYAN}[${prefix}]${NC} $1"
}

# Usage: log_warn "message" ["custom_prefix"]
log_warn() {
    local prefix="${2:-WARN}"
    echo -e "${YELLOW}[${prefix}]${NC} $1"
}

# Usage: log_error "message" ["custom_prefix"]
log_error() {
    local prefix="${2:-ERROR}"
    echo -e "${RED}[${prefix}]${NC} $1"
}

# Print a blank line for spacing (replaces echo "")
# Usage: log_spacer
log_spacer() {
    echo ""
}


# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
    return $?
}

# Ensure a directory exists, create it if it doesn't
# Usage: ensure_directory_exists <directory_path> [description]
#   directory_path: path to the directory
#   description: optional description for logging (defaults to directory name)
ensure_directory_exists() {
    local dir_path="$1"
    local description="${2:-$(basename "$dir_path")}"

    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path"
        return "$EXIT_SUCCESS"
    fi
    return "$EXIT_ERROR"  # Directory already exists
}

# Check if a file exists
# Usage: file_exists <file_path>
file_exists() {
    [ -f "$1" ]
    return $?
}

# Check if a directory exists
# Usage: directory_exists <directory_path>
directory_exists() {
    [ -d "$1" ]
    return $?
}
