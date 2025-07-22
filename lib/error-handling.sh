#!/bin/bash
# =============================================================================
# Error Handling Library
# Comprehensive error handling patterns and utilities
# =============================================================================

# =============================================================================
# COLOR DEFINITIONS (fallback if not already defined)
# =============================================================================

# Only define colors if not already set (to avoid conflicts with common library)
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
fi

# =============================================================================
# ERROR HANDLING CONFIGURATION
# =============================================================================

# Error handling modes
readonly ERROR_MODE_STRICT="strict"        # Exit on any error
readonly ERROR_MODE_RESILIENT="resilient"  # Continue with warnings
readonly ERROR_MODE_INTERACTIVE="interactive" # Prompt user on errors

# Default error handling configuration
export ERROR_HANDLING_MODE="${ERROR_HANDLING_MODE:-$ERROR_MODE_STRICT}"
export ERROR_LOG_FILE="${ERROR_LOG_FILE:-/tmp/ai-starter-kit-errors.log}"
export ERROR_NOTIFICATION_ENABLED="${ERROR_NOTIFICATION_ENABLED:-false}"
export ERROR_CLEANUP_ENABLED="${ERROR_CLEANUP_ENABLED:-true}"

# =============================================================================
# ERROR LOGGING AND TRACKING
# =============================================================================

# Initialize error tracking
ERROR_COUNT=0
WARNING_COUNT=0
LAST_ERROR=""
ERROR_CONTEXT=""
ERROR_STACK=()

init_error_handling() {
    local mode="${1:-$ERROR_MODE_STRICT}"
    local log_file="${2:-$ERROR_LOG_FILE}"
    
    export ERROR_HANDLING_MODE="$mode"
    export ERROR_LOG_FILE="$log_file"
    
    # Initialize error log
    echo "=== Error Log Initialized at $(date) ===" > "$ERROR_LOG_FILE"
    echo "PID: $$" >> "$ERROR_LOG_FILE"
    echo "Script: ${BASH_SOURCE[1]:-unknown}" >> "$ERROR_LOG_FILE"
    echo "Mode: $ERROR_HANDLING_MODE" >> "$ERROR_LOG_FILE"
    echo "" >> "$ERROR_LOG_FILE"
    
    # Set up error trapping based on mode
    case "$mode" in
        "$ERROR_MODE_STRICT")
            set -euo pipefail
            trap 'handle_script_error $? $LINENO $BASH_COMMAND' ERR
            ;;
        "$ERROR_MODE_RESILIENT")
            set -uo pipefail
            trap 'handle_script_error $? $LINENO $BASH_COMMAND' ERR
            ;;
        "$ERROR_MODE_INTERACTIVE")
            set -uo pipefail
            trap 'handle_script_error $? $LINENO $BASH_COMMAND' ERR
            ;;
    esac
    
    # Set up exit trap for cleanup
    trap cleanup_on_exit EXIT
    
    log_debug "Error handling initialized in $mode mode"
}

# =============================================================================
# ENHANCED LOGGING FUNCTIONS
# =============================================================================

log_error() {
    local message="$1"
    local context="${2:-}"
    local exit_code="${3:-1}"
    
    ((ERROR_COUNT++))
    LAST_ERROR="$message"
    ERROR_CONTEXT="$context"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to console
    echo -e "${RED}[ERROR] $message${NC}" >&2
    if [ -n "$context" ]; then
        echo -e "${RED}        Context: $context${NC}" >&2
    fi
    
    # Log to file
    echo "[$timestamp] ERROR: $message" >> "$ERROR_LOG_FILE"
    if [ -n "$context" ]; then
        echo "[$timestamp]        Context: $context" >> "$ERROR_LOG_FILE"
    fi
    
    # Add to error stack
    ERROR_STACK+=("[$timestamp] $message")
    
    # Send notification if enabled
    if [ "$ERROR_NOTIFICATION_ENABLED" = "true" ]; then
        send_error_notification "$message" "$context"
    fi
    
    return "$exit_code"
}

log_warning() {
    local message="$1"
    local context="${2:-}"
    
    ((WARNING_COUNT++))
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to console
    echo -e "${YELLOW}[WARNING] $message${NC}" >&2
    if [ -n "$context" ]; then
        echo -e "${YELLOW}          Context: $context${NC}" >&2
    fi
    
    # Log to file
    echo "[$timestamp] WARNING: $message" >> "$ERROR_LOG_FILE"
    if [ -n "$context" ]; then
        echo "[$timestamp]          Context: $context" >> "$ERROR_LOG_FILE"
    fi
}

log_debug() {
    local message="$1"
    local context="${2:-}"
    
    # Only log debug messages if debug mode is enabled
    if [ "${DEBUG:-false}" = "true" ]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        echo -e "${CYAN}[DEBUG] $message${NC}" >&2
        if [ -n "$context" ]; then
            echo -e "${CYAN}        Context: $context${NC}" >&2
        fi
        
        echo "[$timestamp] DEBUG: $message" >> "$ERROR_LOG_FILE"
        if [ -n "$context" ]; then
            echo "[$timestamp]        Context: $context" >> "$ERROR_LOG_FILE"
        fi
    fi
}

# =============================================================================
# ERROR RECOVERY AND RETRY MECHANISMS
# =============================================================================

retry_command() {
    local max_attempts="$1"
    local delay="$2"
    local description="$3"
    shift 3
    local command=("$@")
    
    local attempt=1
    local exit_code=0
    
    log_debug "Starting retry loop for: $description"
    
    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts: ${command[*]}"
        
        if "${command[@]}"; then
            log_debug "Command succeeded on attempt $attempt"
            return 0
        else
            exit_code=$?
            log_warning "Attempt $attempt/$max_attempts failed (exit code: $exit_code)" "$description"
            
            if [ $attempt -lt $max_attempts ]; then
                log_debug "Waiting ${delay}s before retry..."
                sleep "$delay"
            fi
            
            ((attempt++))
        fi
    done
    
    log_error "Command failed after $max_attempts attempts" "$description" "$exit_code"
    return "$exit_code"
}

retry_with_backoff() {
    local max_attempts="$1"
    local initial_delay="$2"
    local backoff_multiplier="$3"
    local description="$4"
    shift 4
    local command=("$@")
    
    local attempt=1
    local delay="$initial_delay"
    local exit_code=0
    
    log_debug "Starting exponential backoff retry for: $description"
    
    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts (delay: ${delay}s): ${command[*]}"
        
        if "${command[@]}"; then
            log_debug "Command succeeded on attempt $attempt"
            return 0
        else
            exit_code=$?
            log_warning "Attempt $attempt/$max_attempts failed (exit code: $exit_code)" "$description"
            
            if [ $attempt -lt $max_attempts ]; then
                log_debug "Waiting ${delay}s before retry (exponential backoff)..."
                sleep "$delay"
                delay=$(echo "$delay * $backoff_multiplier" | bc -l | cut -d. -f1)
            fi
            
            ((attempt++))
        fi
    done
    
    log_error "Command failed after $max_attempts attempts with exponential backoff" "$description" "$exit_code"
    return "$exit_code"
}

# =============================================================================
# SCRIPT ERROR HANDLING
# =============================================================================

handle_script_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"
    
    local script_name="${BASH_SOURCE[1]:-unknown script}"
    local function_name="${FUNCNAME[1]:-main}"
    
    log_error "Script error in $script_name:$line_number" \
              "Function: $function_name, Command: $command, Exit code: $exit_code" \
              "$exit_code"
    
    # Generate stack trace
    generate_stack_trace
    
    case "$ERROR_HANDLING_MODE" in
        "$ERROR_MODE_STRICT")
            log_error "Strict mode: Exiting due to error"
            exit "$exit_code"
            ;;
        "$ERROR_MODE_RESILIENT")
            log_warning "Resilient mode: Continuing despite error"
            return 0
            ;;
        "$ERROR_MODE_INTERACTIVE")
            handle_interactive_error "$exit_code" "$line_number" "$command"
            ;;
    esac
}

handle_interactive_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"
    
    echo
    warning "An error occurred. What would you like to do?"
    echo "1) Continue execution (ignore error)"
    echo "2) Retry the failed command"
    echo "3) Exit the script"
    echo "4) Drop to debug shell"
    echo
    
    while true; do
        read -p "Choose an option [1-4]: " -r choice
        case "$choice" in
            1)
                log_warning "User chose to continue despite error"
                return 0
                ;;
            2)
                log_debug "User chose to retry command: $command"
                if eval "$command"; then
                    success "Retry succeeded"
                    return 0
                else
                    log_error "Retry failed"
                    handle_interactive_error "$?" "$line_number" "$command"
                fi
                ;;
            3)
                log_warning "User chose to exit"
                exit "$exit_code"
                ;;
            4)
                log_debug "Dropping to debug shell"
                echo "Debug shell (type 'exit' to return):"
                bash --rcfile <(echo "PS1='DEBUG> '")
                ;;
            *)
                echo "Invalid choice. Please select 1-4."
                ;;
        esac
    done
}

# =============================================================================
# STACK TRACE AND DEBUGGING
# =============================================================================

generate_stack_trace() {
    local i=0
    log_error "Stack trace:"
    
    while caller $i >/dev/null 2>&1; do
        local line_info
        line_info=$(caller $i)
        local line_number="${line_info%% *}"
        local function_name="${line_info#* }"
        function_name="${function_name%% *}"
        local script_name="${line_info##* }"
        
        log_error "  [$i] $script_name:$line_number in $function_name()"
        ((i++))
    done
}

dump_environment() {
    log_debug "Environment dump requested"
    
    local env_file="/tmp/environment-dump-$$.txt"
    
    {
        echo "=== Environment Dump at $(date) ==="
        echo "Script: ${BASH_SOURCE[1]:-unknown}"
        echo "PID: $$"
        echo "PWD: $PWD"
        echo "User: $(whoami)"
        echo ""
        echo "=== Variables ==="
        env | sort
        echo ""
        echo "=== Function Stack ==="
        declare -F
        echo ""
        echo "=== Error Statistics ==="
        echo "Error Count: $ERROR_COUNT"
        echo "Warning Count: $WARNING_COUNT"
        echo "Last Error: $LAST_ERROR"
        echo "Error Context: $ERROR_CONTEXT"
    } > "$env_file"
    
    log_debug "Environment dumped to: $env_file"
    echo "$env_file"
}

# =============================================================================
# RESOURCE CLEANUP
# =============================================================================

register_cleanup_function() {
    local cleanup_function="$1"
    local description="${2:-Cleanup function}"
    
    if [ -z "${CLEANUP_FUNCTIONS:-}" ]; then
        CLEANUP_FUNCTIONS=""
    fi
    
    if [ -z "$CLEANUP_FUNCTIONS" ]; then
        CLEANUP_FUNCTIONS="$cleanup_function"
    else
        CLEANUP_FUNCTIONS="$CLEANUP_FUNCTIONS $cleanup_function"
    fi
    log_debug "Registered cleanup function: $cleanup_function ($description)"
}

cleanup_on_exit() {
    local exit_code=$?
    
    log_debug "Cleanup on exit triggered (exit code: $exit_code)"
    
    if [ "$ERROR_CLEANUP_ENABLED" = "true" ] && [ -n "${CLEANUP_FUNCTIONS:-}" ]; then
        local func_count=$(echo "$CLEANUP_FUNCTIONS" | wc -w)
        log_debug "Running $func_count cleanup functions..."
        
        for cleanup_func in $CLEANUP_FUNCTIONS; do
            log_debug "Running cleanup function: $cleanup_func"
            if ! "$cleanup_func"; then
                log_warning "Cleanup function failed: $cleanup_func"
            fi
        done
    fi
    
    # Final error summary
    if [ $ERROR_COUNT -gt 0 ] || [ $WARNING_COUNT -gt 0 ]; then
        log_debug "Session summary: $ERROR_COUNT errors, $WARNING_COUNT warnings"
        echo "Error log: $ERROR_LOG_FILE" >&2
    fi
}

# =============================================================================
# VALIDATION WITH ERROR HANDLING
# =============================================================================

validate_required_command() {
    local command="$1"
    local package_hint="${2:-}"
    local install_command="${3:-}"
    
    if ! command -v "$command" &> /dev/null; then
        local error_msg="Required command not found: $command"
        local context=""
        
        if [ -n "$package_hint" ]; then
            context="Package: $package_hint"
        fi
        
        if [ -n "$install_command" ]; then
            context="$context, Install with: $install_command"
        fi
        
        log_error "$error_msg" "$context"
        return 1
    fi
    
    log_debug "Command available: $command"
    return 0
}

validate_required_file() {
    local file_path="$1"
    local description="${2:-file}"
    local auto_create="${3:-false}"
    
    if [ ! -f "$file_path" ]; then
        if [ "$auto_create" = "true" ]; then
            log_warning "Creating missing $description: $file_path"
            touch "$file_path" || {
                log_error "Failed to create $description: $file_path"
                return 1
            }
        else
            log_error "Required $description not found: $file_path"
            return 1
        fi
    fi
    
    log_debug "File validated: $file_path"
    return 0
}

validate_required_directory() {
    local dir_path="$1"
    local description="${2:-directory}"
    local auto_create="${3:-false}"
    
    if [ ! -d "$dir_path" ]; then
        if [ "$auto_create" = "true" ]; then
            log_warning "Creating missing $description: $dir_path"
            mkdir -p "$dir_path" || {
                log_error "Failed to create $description: $dir_path"
                return 1
            }
        else
            log_error "Required $description not found: $dir_path"
            return 1
        fi
    fi
    
    log_debug "Directory validated: $dir_path"
    return 0
}

# =============================================================================
# AWS-SPECIFIC ERROR HANDLING
# =============================================================================

handle_aws_error() {
    local aws_command="$1"
    local error_output="$2"
    local exit_code="$3"
    
    # Parse common AWS error patterns
    local error_type=""
    local error_message=""
    local suggested_action=""
    
    if echo "$error_output" | grep -q "InvalidUserID.NotFound"; then
        error_type="Authentication Error"
        error_message="AWS credentials are invalid or expired"
        suggested_action="Run 'aws configure' or check your AWS credentials"
    elif echo "$error_output" | grep -q "UnauthorizedOperation"; then
        error_type="Permission Error"
        error_message="Insufficient permissions for the requested operation"
        suggested_action="Check IAM policies and permissions"
    elif echo "$error_output" | grep -q "RequestLimitExceeded"; then
        error_type="Rate Limiting"
        error_message="AWS API rate limit exceeded"
        suggested_action="Wait and retry, or reduce request frequency"
    elif echo "$error_output" | grep -q "InstanceLimitExceeded"; then
        error_type="Resource Limit"
        error_message="Instance limit exceeded in region"
        suggested_action="Try a different region or request limit increase"
    elif echo "$error_output" | grep -q "InsufficientInstanceCapacity"; then
        error_type="Capacity Error"
        error_message="Insufficient capacity for instance type"
        suggested_action="Try different instance type or availability zone"
    else
        error_type="AWS Error"
        error_message="Unknown AWS error"
        suggested_action="Check AWS documentation or contact support"
    fi
    
    log_error "$error_type: $error_message" \
              "Command: $aws_command, Suggested action: $suggested_action" \
              "$exit_code"
    
    return "$exit_code"
}

# =============================================================================
# NOTIFICATION SYSTEM
# =============================================================================

send_error_notification() {
    local error_message="$1"
    local context="${2:-}"
    
    # Simple notification implementations
    # In a real system, this could integrate with Slack, email, SNS, etc.
    
    if command -v notify-send &> /dev/null; then
        notify-send "AI Starter Kit Error" "$error_message"
    fi
    
    # Log notification attempt
    log_debug "Error notification sent: $error_message"
}

# =============================================================================
# ERROR RECOVERY STRATEGIES
# =============================================================================

suggest_error_recovery() {
    local error_context="$1"
    local suggestions=()
    
    case "$error_context" in
        *"aws"*|*"AWS"*)
            suggestions+=(
                "Check AWS credentials: aws sts get-caller-identity"
                "Verify AWS region: aws configure get region"
                "Check service limits in AWS console"
                "Try a different availability zone"
            )
            ;;
        *"docker"*|*"Docker"*)
            suggestions+=(
                "Check Docker daemon: docker info"
                "Free up disk space: docker system prune"
                "Restart Docker service: sudo systemctl restart docker"
                "Check Docker permissions: sudo usermod -aG docker \$USER"
            )
            ;;
        *"ssh"*|*"SSH"*)
            suggestions+=(
                "Check key file permissions: chmod 600 keyfile.pem"
                "Verify security group allows SSH (port 22)"
                "Check instance public IP and connectivity"
                "Wait for instance to fully initialize"
            )
            ;;
        *"network"*|*"connection"*)
            suggestions+=(
                "Check internet connectivity"
                "Verify firewall settings"
                "Try different DNS servers"
                "Check proxy settings"
            )
            ;;
    esac
    
    if [ ${#suggestions[@]} -gt 0 ]; then
        log_warning "Recovery suggestions for '$error_context':"
        for suggestion in "${suggestions[@]}"; do
            log_warning "  • $suggestion"
        done
    fi
}

# =============================================================================
# ERROR REPORTING
# =============================================================================

generate_error_report() {
    local report_file="${1:-/tmp/error-report-$(date +%Y%m%d-%H%M%S).txt}"
    
    {
        echo "=== AI Starter Kit Error Report ==="
        echo "Generated: $(date)"
        echo "Script: ${BASH_SOURCE[1]:-unknown}"
        echo "PID: $$"
        echo ""
        echo "=== Error Statistics ==="
        echo "Total Errors: $ERROR_COUNT"
        echo "Total Warnings: $WARNING_COUNT"
        echo "Last Error: $LAST_ERROR"
        echo "Error Context: $ERROR_CONTEXT"
        echo ""
        echo "=== Error Stack ==="
        for error in "${ERROR_STACK[@]}"; do
            echo "$error"
        done
        echo ""
        echo "=== System Information ==="
        echo "OS: $(uname -a)"
        echo "User: $(whoami)"
        echo "PWD: $PWD"
        echo "PATH: $PATH"
        echo ""
        echo "=== Environment Variables ==="
        env | grep -E '^(AWS_|STACK_|ERROR_|DEBUG)' | sort
        echo ""
        echo "=== Error Log ==="
        if [ -f "$ERROR_LOG_FILE" ]; then
            cat "$ERROR_LOG_FILE"
        else
            echo "Error log file not found: $ERROR_LOG_FILE"
        fi
    } > "$report_file"
    
    log_debug "Error report generated: $report_file"
    echo "$report_file"
}