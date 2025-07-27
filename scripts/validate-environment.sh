#!/bin/bash
# =============================================================================
# Environment Validation Script for GeuseMaker
# Comprehensive validation of all environment variables and configurations
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="validate-environment"
readonly SCRIPT_VERSION="1.0.0"
readonly VALIDATION_LOG="/var/log/geuse-validation.log"
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Required critical variables
readonly CRITICAL_VARIABLES="POSTGRES_PASSWORD N8N_ENCRYPTION_KEY N8N_USER_MANAGEMENT_JWT_SECRET"

# Required optional variables with defaults
readonly OPTIONAL_VARIABLES="POSTGRES_DB POSTGRES_USER AWS_REGION ENVIRONMENT STACK_NAME"

# Required service variables
readonly SERVICE_VARIABLES="WEBHOOK_URL ENABLE_METRICS LOG_LEVEL COMPOSE_FILE"

# =============================================================================
# LOGGING SYSTEM
# =============================================================================

log() {
    local level="INFO"
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$VALIDATION_LOG"
}

error() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [ERROR] $message" | tee -a "$VALIDATION_LOG" >&2
}

success() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [SUCCESS] $message" | tee -a "$VALIDATION_LOG"
}

warning() {
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [WARNING] $message" | tee -a "$VALIDATION_LOG"
}

# =============================================================================
# VARIABLE VALIDATION FUNCTIONS
# =============================================================================

# Validate that a variable is set and not empty
validate_variable_set() {
    local var_name="$1"
    local var_value
    eval "var_value=\${$var_name:-}"
    
    if [ -z "$var_value" ]; then
        error "Variable $var_name is not set or empty"
        return 1
    else
        log "✓ $var_name is set (${#var_value} characters)"
        return 0
    fi
}

# Validate critical variables with security checks
validate_critical_variables() {
    log "Validating critical variables..."
    local validation_passed=true
    
    for var in $CRITICAL_VARIABLES; do
        local value
        eval "value=\${$var:-}"
        
        if [ -z "$value" ]; then
            error "Critical variable $var is not set"
            validation_passed=false
            continue
        fi
        
        # Check minimum length
        if [ ${#value} -lt 8 ]; then
            error "Critical variable $var is too short (${#value} chars, minimum 8)"
            validation_passed=false
            continue
        fi
        
        # Check for common insecure values
        case "$var" in
            POSTGRES_PASSWORD)
                case "$value" in
                    password|postgres|admin|root|test)
                        error "POSTGRES_PASSWORD uses a common insecure value"
                        validation_passed=false
                        continue
                        ;;
                esac
                ;;
            N8N_ENCRYPTION_KEY)
                if [ ${#value} -lt 32 ]; then
                    error "N8N_ENCRYPTION_KEY is too short for security (${#value} chars, minimum 32)"
                    validation_passed=false
                    continue
                fi
                ;;
        esac
        
        success "✓ $var is valid (${#value} characters)"
    done
    
    if [ "$validation_passed" = "true" ]; then
        success "All critical variables are valid"
        return 0
    else
        error "Critical variable validation failed"
        return 1
    fi
}

# =============================================================================
# MAIN VALIDATION FUNCTION
# =============================================================================

run_validation() {
    local validation_mode="${1:-full}"
    local exit_on_error="${2:-true}"
    
    log "Starting environment validation (mode: $validation_mode)..."
    local validation_errors=0
    
    # Load variable management library
    if [ -f "$PROJECT_ROOT/lib/variable-management.sh" ]; then
        log "Loading variable management library..."
        source "$PROJECT_ROOT/lib/variable-management.sh"
        
        # Initialize variables if not already done
        if command -v init_all_variables >/dev/null 2>&1; then
            log "Initializing variables..."
            if ! init_all_variables; then
                warning "Variable initialization had issues"
                validation_errors=$((validation_errors + 1))
            fi
        fi
    else
        error "Variable management library not found"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Run validation checks
    case "$validation_mode" in
        variables)
            log "Running variables-only validation..."
            
            if ! validate_critical_variables; then
                validation_errors=$((validation_errors + 1))
            fi
            ;;
            
        *)
            error "Unknown validation mode: $validation_mode"
            validation_errors=$((validation_errors + 1))
            ;;
    esac
    
    # Report results
    if [ $validation_errors -eq 0 ]; then
        success "🎉 All validation checks passed!"
        return 0
    else
        error "❌ Validation failed with $validation_errors errors"
        if [ "$exit_on_error" = "true" ]; then
            exit 1
        else
            return 1
        fi
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Ensure log directory exists
mkdir -p "$(dirname "$VALIDATION_LOG")"

log "Starting GeuseMaker environment validation..."
log "Script: $SCRIPT_NAME v$SCRIPT_VERSION"

# Run validation
run_validation "variables" "false"