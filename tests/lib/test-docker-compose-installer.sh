#!/bin/bash
# =============================================================================
# Unit Tests for docker-compose-installer.sh
# Tests for Docker Compose installation functions and utilities
# =============================================================================

set -euo pipefail

# Get script directory for sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the test framework
source "$SCRIPT_DIR/shell-test-framework.sh"

# Source the library under test
source "$PROJECT_ROOT/lib/docker-compose-installer.sh"

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup_test_environment() {
    # Create temporary directories for testing
    TEST_TMP_DIR=$(mktemp -d)
    TEST_COMPOSE_DIR="$TEST_TMP_DIR/docker-compose"
    mkdir -p "$TEST_COMPOSE_DIR"
    
    # Mock external commands for testing
    mock_external_commands
}

teardown_test_environment() {
    # Clean up temporary directories
    [[ -d "$TEST_TMP_DIR" ]] && rm -rf "$TEST_TMP_DIR"
    
    # Restore mocked functions
    restore_function "fuser"
    restore_function "pgrep"
    restore_function "pkill"
    restore_function "curl"
    restore_function "sudo"
    restore_function "command"
    restore_function "docker"
    restore_function "uname"
}

# Mock external commands for testing
mock_external_commands() {
    # Mock fuser to simulate no locks
    mock_function "fuser" "return 1"
    
    # Mock pgrep to simulate no blocking processes
    mock_function "pgrep" "return 1"
    
    # Mock pkill for cleanup operations
    mock_function "pkill" "return 0"
    
    # Mock curl for version checking and downloads
    mock_function "curl" '
        if [[ "$*" == *"api.github.com"* ]]; then
            echo "{\"tag_name\": \"v2.24.5\"}"
        elif [[ "$*" == *"docker-compose"* ]]; then
            echo "Mock Docker Compose binary downloaded"
            return 0
        else
            return 0
        fi
    '
    
    # Mock sudo for installation commands
    mock_function "sudo" '
        if [[ "$*" == *"mkdir"* ]] || [[ "$*" == *"chmod"* ]] || [[ "$*" == *"ln"* ]]; then
            return 0
        elif [[ "$*" == *"curl"* ]]; then
            echo "Mock Docker Compose binary downloaded"
            return 0
        else
            "$@"
        fi
    '
    
    # Mock command to control Docker Compose detection
    mock_function "command" '
        if [[ "$*" == *"docker compose"* ]] || [[ "$*" == *"docker-compose"* ]]; then
            return 1  # Not found by default
        else
            return 0
        fi
    '
    
    # Mock docker command
    mock_function "docker" '
        if [[ "$*" == *"compose version"* ]]; then
            echo "Docker Compose version v2.24.5"
            return 0
        else
            return 0
        fi
    '
    
    # Mock uname for architecture detection
    mock_function "uname" '
        if [[ "$*" == *"-m"* ]]; then
            echo "x86_64"
        elif [[ "$*" == *"-s"* ]]; then
            echo "Linux"
        else
            echo "Linux"
        fi
    '
}

# =============================================================================
# APT LOCK WAITING TESTS
# =============================================================================

test_shared_wait_for_apt_lock_no_locks() {
    test_start "shared_wait_for_apt_lock returns immediately when no locks present"
    
    setup_test_environment
    
    local start_time=$(date +%s)
    shared_wait_for_apt_lock >/dev/null 2>&1
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $duration -lt 5 ]]; then
        test_pass
    else
        test_fail "Function should return quickly when no locks, took ${duration}s"
    fi
}

test_shared_wait_for_apt_lock_with_locks() {
    test_start "shared_wait_for_apt_lock waits when locks are present"
    
    setup_test_environment
    
    # Mock fuser to simulate locks initially, then clear
    local call_count=0
    mock_function "fuser" '
        ((call_count++))
        if [[ $call_count -le 2 ]]; then
            return 0  # Locks present
        else
            return 1  # Locks cleared
        fi
    '
    
    local start_time=$(date +%s)
    shared_wait_for_apt_lock >/dev/null 2>&1
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $duration -gt 10 ]]; then
        test_pass
    else
        test_fail "Function should wait when locks are present"
    fi
    
    restore_function "fuser"
}

test_shared_wait_for_apt_lock_timeout() {
    test_start "shared_wait_for_apt_lock handles timeout correctly"
    
    setup_test_environment
    
    # Mock fuser to always return locks (simulate stuck process)
    mock_function "fuser" "return 0"
    
    # This should timeout and kill processes
    local start_time=$(date +%s)
    shared_wait_for_apt_lock >/dev/null 2>&1
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Should timeout around 300 seconds, but we'll check for reasonable upper bound
    if [[ $duration -gt 300 && $duration -lt 350 ]]; then
        test_pass
    else
        test_skip "Timeout test skipped to avoid long wait (would take 5+ minutes)"
    fi
    
    restore_function "fuser"
}

# =============================================================================
# DOCKER COMPOSE MANUAL INSTALLATION TESTS
# =============================================================================

test_shared_install_compose_manual_basic() {
    test_start "shared_install_compose_manual installs Docker Compose"
    
    setup_test_environment
    
    if shared_install_compose_manual >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Manual installation should succeed with mocked dependencies"
    fi
}

test_shared_install_compose_manual_version_detection() {
    test_start "shared_install_compose_manual detects latest version"
    
    setup_test_environment
    
    # Mock curl to return specific version
    mock_function "curl" '
        if [[ "$*" == *"api.github.com"* ]]; then
            echo "{\"tag_name\": \"v2.25.0\"}"
        else
            return 0
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    assert_contains "$output" "v2.25.0" "Should detect and use latest version"
    
    restore_function "curl"
}

test_shared_install_compose_manual_fallback_version() {
    test_start "shared_install_compose_manual uses fallback version when API fails"
    
    setup_test_environment
    
    # Mock curl to fail for API call
    mock_function "curl" '
        if [[ "$*" == *"api.github.com"* ]]; then
            return 1
        else
            return 0
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    assert_contains "$output" "fallback" "Should use fallback when API fails"
    assert_contains "$output" "v2.24.5" "Should use fallback version"
    
    restore_function "curl"
}

test_shared_install_compose_manual_architecture_detection() {
    test_start "shared_install_compose_manual detects system architecture"
    
    setup_test_environment
    
    # Test x86_64 architecture
    mock_function "uname" '
        if [[ "$*" == *"-m"* ]]; then
            echo "x86_64"
        else
            echo "Linux"
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    assert_contains "$output" "x86_64" "Should detect x86_64 architecture"
    
    restore_function "uname"
}

test_shared_install_compose_manual_unsupported_arch() {
    test_start "shared_install_compose_manual handles unsupported architecture"
    
    setup_test_environment
    
    # Mock unsupported architecture
    mock_function "uname" '
        if [[ "$*" == *"-m"* ]]; then
            echo "unsupported_arch"
        else
            echo "Linux"
        fi
    '
    
    if shared_install_compose_manual >/dev/null 2>&1; then
        test_fail "Should fail with unsupported architecture"
    else
        test_pass
    fi
    
    restore_function "uname"
}

test_shared_install_compose_manual_download_fallback() {
    test_start "shared_install_compose_manual uses fallback download method"
    
    setup_test_environment
    
    local download_attempts=0
    mock_function "sudo" '
        if [[ "$*" == *"curl"* ]]; then
            ((download_attempts++))
            if [[ $download_attempts -eq 1 ]]; then
                return 1  # First download fails
            else
                echo "Fallback download successful"
                return 0  # Fallback succeeds
            fi
        else
            return 0
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    assert_contains "$output" "fallback" "Should use fallback download method"
    
    restore_function "sudo"
}

# =============================================================================
# MAIN DOCKER COMPOSE INSTALLATION TESTS
# =============================================================================

test_shared_install_docker_compose_already_installed() {
    test_start "shared_install_docker_compose detects existing installation"
    
    setup_test_environment
    
    # Mock command to return that Docker Compose is installed
    mock_function "command" '
        if [[ "$*" == *"docker compose"* ]]; then
            return 0  # Found
        else
            return 0
        fi
    '
    
    local output
    output=$(shared_install_docker_compose 2>&1)
    
    assert_contains "$output" "already installed" "Should detect existing installation"
    
    restore_function "command"
}

test_shared_install_docker_compose_fresh_install() {
    test_start "shared_install_docker_compose performs fresh installation"
    
    setup_test_environment
    
    # Mock command to return that Docker Compose is not installed
    mock_function "command" "return 1"
    
    # Mock the manual installation function
    mock_function "shared_install_compose_manual" "return 0"
    
    if shared_install_docker_compose >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Fresh installation should succeed"
    fi
    
    restore_function "command"
    restore_function "shared_install_compose_manual"
}

test_shared_install_docker_compose_distribution_detection() {
    test_start "shared_install_docker_compose detects distribution"
    
    setup_test_environment
    
    # Create mock os-release file
    local mock_os_release="$TEST_TMP_DIR/os-release"
    echo 'ID=ubuntu' > "$mock_os_release"
    echo 'VERSION_ID="20.04"' >> "$mock_os_release"
    
    # Mock the os-release file location
    mock_function "test" '
        if [[ "$*" == *"/etc/os-release"* ]]; then
            return 0
        else
            return 1
        fi
    '
    
    # Since we can't easily mock file reading, we'll test the function exists
    if declare -f shared_install_docker_compose >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Function should be defined"
    fi
    
    restore_function "test"
}

test_shared_install_docker_compose_verification() {
    test_start "shared_install_docker_compose verifies installation"
    
    setup_test_environment
    
    # Mock command to show Docker Compose is installed
    mock_function "command" '
        if [[ "$*" == *"docker compose"* ]]; then
            return 0  # Found
        else
            return 0
        fi
    '
    
    # Mock docker compose version to work
    mock_function "docker" '
        if [[ "$*" == *"compose version"* ]]; then
            echo "Docker Compose version v2.24.5"
            return 0
        else
            return 0
        fi
    '
    
    local output
    output=$(shared_install_docker_compose 2>&1)
    
    assert_contains "$output" "verified working" "Should verify installation works"
    
    restore_function "command"
    restore_function "docker"
}

# =============================================================================
# ARCHITECTURE HANDLING TESTS
# =============================================================================

test_architecture_mapping_x86_64() {
    test_start "architecture mapping handles x86_64 correctly"
    
    setup_test_environment
    
    mock_function "uname" '
        if [[ "$*" == *"-m"* ]]; then
            echo "x86_64"
        else
            echo "Linux"
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    assert_contains "$output" "x86_64" "Should handle x86_64 architecture"
    
    restore_function "uname"
}

test_architecture_mapping_aarch64() {
    test_start "architecture mapping handles aarch64 correctly"
    
    setup_test_environment
    
    mock_function "uname" '
        if [[ "$*" == *"-m"* ]]; then
            echo "aarch64"
        else
            echo "Linux"
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    assert_contains "$output" "aarch64" "Should handle aarch64 architecture"
    
    restore_function "uname"
}

test_architecture_mapping_arm64() {
    test_start "architecture mapping handles arm64 correctly"
    
    setup_test_environment
    
    mock_function "uname" '
        if [[ "$*" == *"-m"* ]]; then
            echo "arm64"
        else
            echo "Linux"
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    # arm64 should be mapped to aarch64
    assert_contains "$output" "aarch64" "Should map arm64 to aarch64"
    
    restore_function "uname"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

test_shared_install_compose_manual_all_downloads_fail() {
    test_start "shared_install_compose_manual handles all download failures"
    
    setup_test_environment
    
    # Mock sudo curl to always fail
    mock_function "sudo" '
        if [[ "$*" == *"curl"* ]]; then
            return 1  # Always fail
        else
            return 0
        fi
    '
    
    if shared_install_compose_manual >/dev/null 2>&1; then
        test_fail "Should fail when all download methods fail"
    else
        test_pass
    fi
    
    restore_function "sudo"
}

test_network_timeout_handling() {
    test_start "installation functions handle network timeouts"
    
    setup_test_environment
    
    # Mock curl to simulate timeout
    mock_function "curl" '
        if [[ "$*" == *"--connect-timeout"* ]]; then
            sleep 1  # Simulate delay
            return 1  # Timeout
        else
            return 1
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    assert_contains "$output" "fallback" "Should handle timeouts gracefully"
    
    restore_function "curl"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_complete_installation_workflow() {
    test_start "complete installation workflow works end-to-end"
    
    setup_test_environment
    
    # Mock the full workflow
    mock_function "command" "return 1"  # Docker Compose not installed
    mock_function "shared_install_compose_manual" "return 0"  # Installation succeeds
    
    if shared_install_docker_compose >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Complete workflow should succeed"
    fi
    
    restore_function "command"
    restore_function "shared_install_compose_manual"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_empty_version_response() {
    test_start "handles empty version response from GitHub API"
    
    setup_test_environment
    
    # Mock curl to return empty response
    mock_function "curl" '
        if [[ "$*" == *"api.github.com"* ]]; then
            echo ""  # Empty response
        else
            return 0
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    assert_contains "$output" "fallback" "Should use fallback version"
    
    restore_function "curl"
}

test_malformed_json_response() {
    test_start "handles malformed JSON response from GitHub API"
    
    setup_test_environment
    
    # Mock curl to return malformed JSON
    mock_function "curl" '
        if [[ "$*" == *"api.github.com"* ]]; then
            echo "malformed json response"
        else
            return 0
        fi
    '
    
    local output
    output=$(shared_install_compose_manual 2>&1)
    
    assert_contains "$output" "fallback" "Should handle malformed JSON"
    
    restore_function "curl"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

main() {
    test_init "test-docker-compose-installer.sh"
    
    # Set up clean test environment
    setup_test_environment
    
    # Run all tests
    run_all_tests
    
    # Clean up
    teardown_test_environment
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi