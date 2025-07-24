#!/bin/bash

# =============================================================================
# Security Check Script for GeuseMaker
# =============================================================================
# Comprehensive security audit and validation for the AI starter kit
# Run this before deployment to identify security issues
# =============================================================================

set -euo pipefail

# Load security validation library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/security-validation.sh" ]]; then
    source "$SCRIPT_DIR/security-validation.sh"
else
    echo "Error: Security validation library not found at $SCRIPT_DIR/security-validation.sh"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# SECURITY AUDIT FUNCTIONS
# =============================================================================

# Check for hardcoded secrets in all files
audit_secrets() {
    echo -e "${BLUE}=== Auditing for Hardcoded Secrets ===${NC}"
    
    local issues=0
    local patterns=(
        "password.*="
        "secret.*="
        "key.*="
        "token.*="
        "aws_access_key"
        "aws_secret"
        "api_key"
        "bearer.*token"
    )
    
    # Files to check
    local file_types=(
        "*.sh" "*.py" "*.js" "*.json" "*.yml" "*.yaml" 
        "*.env*" "*.config" "*.conf" "*.toml"
    )
    
    for pattern in "${patterns[@]}"; do
        echo "Checking for pattern: $pattern"
        
        for file_type in "${file_types[@]}"; do
            while IFS= read -r -d '' file; do
                if [[ -f "$file" ]] && grep -qi "$pattern" "$file" 2>/dev/null; then
                    echo -e "${YELLOW}⚠ Potential secret in: $file${NC}"
                    grep -ni "$pattern" "$file" | head -3
                    ((issues++))
                fi
            done < <(find . -name "$file_type" -type f -print0 2>/dev/null)
        done
    done
    
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✓ No obvious hardcoded secrets found${NC}"
    else
        echo -e "${RED}✗ Found $issues potential secret issues${NC}"
    fi
    
    return $issues
}

# Check Docker security configurations
audit_docker_security() {
    echo -e "${BLUE}=== Auditing Docker Security ===${NC}"
    
    local issues=0
    
    # Find all docker-compose files
    while IFS= read -r -d '' file; do
        echo "Checking Docker security in: $file"
        
        # Check for privileged containers
        if grep -q "privileged.*true" "$file" 2>/dev/null; then
            echo -e "${RED}✗ Privileged container found in $file${NC}"
            ((issues++))
        fi
        
        # Check for host network mode
        if grep -q "network_mode.*host" "$file" 2>/dev/null; then
            echo -e "${RED}✗ Host network mode found in $file${NC}"
            ((issues++))
        fi
        
        # Check for CORS wildcards
        if grep -q "CORS.*\*" "$file" 2>/dev/null; then
            echo -e "${YELLOW}⚠ CORS wildcard found in $file${NC}"
            ((issues++))
        fi
        
        # Check for trusted hosts wildcards
        if grep -q 'TRUSTED_HOSTS.*\[\"\*\"\]' "$file" 2>/dev/null; then
            echo -e "${YELLOW}⚠ Trusted hosts wildcard found in $file${NC}"
            ((issues++))
        fi
        
        # Check for root user mounts
        if grep -q ":/.*:.*" "$file" | grep -q "^/" 2>/dev/null; then
            echo -e "${YELLOW}⚠ Root filesystem mount found in $file${NC}"
        fi
        
    done < <(find . -name "docker-compose*.yml" -type f -print0 2>/dev/null)
    
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✓ Docker security checks passed${NC}"
    else
        echo -e "${RED}✗ Found $issues Docker security issues${NC}"
    fi
    
    return $issues
}

# Check file permissions
audit_file_permissions() {
    echo -e "${BLUE}=== Auditing File Permissions ===${NC}"
    
    local issues=0
    
    # Check for world-writable files
    echo "Checking for world-writable files..."
    while IFS= read -r file; do
        echo -e "${RED}✗ World-writable file: $file${NC}"
        ((issues++))
    done < <(find . -type f -perm -002 2>/dev/null)
    
    # Check for overly permissive script files
    echo "Checking script file permissions..."
    while IFS= read -r file; do
        local perms
        perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%A" "$file" 2>/dev/null)
        if [[ "$perms" =~ ^[0-9]*[7][0-9]*$ ]]; then
            echo -e "${YELLOW}⚠ Overly permissive script: $file ($perms)${NC}"
        fi
    done < <(find . -name "*.sh" -o -name "*.py" 2>/dev/null)
    
    # Check for SSH keys with wrong permissions
    while IFS= read -r file; do
        local perms
        perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%A" "$file" 2>/dev/null)
        if [[ "$perms" != "600" ]]; then
            echo -e "${RED}✗ SSH key with wrong permissions: $file ($perms)${NC}"
            ((issues++))
        fi
    done < <(find . -name "*.pem" -o -name "id_*" -o -name "*.key" 2>/dev/null)
    
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✓ File permissions check passed${NC}"
    else
        echo -e "${RED}✗ Found $issues permission issues${NC}"
    fi
    
    return $issues
}

# Check AWS configuration security
audit_aws_config() {
    echo -e "${BLUE}=== Auditing AWS Configuration ===${NC}"
    
    local issues=0
    
    # Check for hardcoded AWS credentials
    if grep -r "aws_access_key\|aws_secret_access_key" . --include="*.sh" --include="*.py" --include="*.json" 2>/dev/null; then
        echo -e "${RED}✗ Hardcoded AWS credentials found${NC}"
        ((issues++))
    fi
    
    # Check for overly permissive IAM policies in scripts
    if grep -r "Effect.*Allow" . --include="*.json" | grep -q "\*" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Potential overly permissive IAM policies${NC}"
    fi
    
    # Check for unencrypted S3 bucket configurations
    if grep -r "s3.*bucket" . --include="*.sh" --include="*.py" 2>/dev/null | grep -v "encrypt" >/dev/null; then
        echo -e "${YELLOW}⚠ S3 bucket configurations should include encryption${NC}"
    fi
    
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✓ AWS configuration checks passed${NC}"
    else
        echo -e "${RED}✗ Found $issues AWS configuration issues${NC}"
    fi
    
    return $issues
}

# Check network security configurations
audit_network_security() {
    echo -e "${BLUE}=== Auditing Network Security ===${NC}"
    
    local issues=0
    
    # Check for open ports in docker-compose files
    while IFS= read -r file; do
        echo "Checking network configuration in: $file"
        
        # Check for port bindings to 0.0.0.0
        if grep -q "0\.0\.0\.0:" "$file" 2>/dev/null; then
            echo -e "${YELLOW}⚠ Services bound to 0.0.0.0 in $file${NC}"
        fi
        
        # Check for excessive port ranges
        if grep -q "[0-9]*-[0-9]*:" "$file" 2>/dev/null; then
            echo -e "${YELLOW}⚠ Port ranges found in $file${NC}"
        fi
        
    done < <(find . -name "docker-compose*.yml" -type f 2>/dev/null)
    
    # Check for insecure protocol usage
    if grep -r "http://" . --include="*.sh" --include="*.py" --include="*.yml" 2>/dev/null | grep -v localhost | grep -v 127.0.0.1; then
        echo -e "${YELLOW}⚠ HTTP (insecure) URLs found - consider using HTTPS${NC}"
    fi
    
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✓ Network security checks passed${NC}"
    else
        echo -e "${RED}✗ Found $issues network security issues${NC}"
    fi
    
    return $issues
}

# Check for vulnerable dependencies
audit_dependencies() {
    echo -e "${BLUE}=== Auditing Dependencies ===${NC}"
    
    local issues=0
    
    # Check Python requirements if they exist
    if [[ -f "requirements.txt" ]]; then
        echo "Checking Python dependencies..."
        # This would require pip-audit or safety tools
        if command -v pip-audit >/dev/null 2>&1; then
            pip-audit --requirement requirements.txt || ((issues++))
        elif command -v safety >/dev/null 2>&1; then
            safety check --requirement requirements.txt || ((issues++))
        else
            echo -e "${YELLOW}⚠ Python security scanners not available (pip-audit, safety)${NC}"
        fi
    fi
    
    # Check for known vulnerable Docker images
    while IFS= read -r file; do
        # Check for outdated base images
        if grep -q "ubuntu:18.04\|debian:9\|alpine:3.1" "$file" 2>/dev/null; then
            echo -e "${YELLOW}⚠ Outdated base images found in $file${NC}"
        fi
        
        # Check for latest tags
        if grep -q ":latest" "$file" 2>/dev/null; then
            echo -e "${YELLOW}⚠ 'latest' tags found in $file - pin specific versions${NC}"
        fi
        
    done < <(find . -name "Dockerfile*" -o -name "docker-compose*.yml" 2>/dev/null)
    
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✓ Dependency checks completed${NC}"
    else
        echo -e "${RED}✗ Found $issues dependency issues${NC}"
    fi
    
    return $issues
}

# =============================================================================
# MAIN SECURITY AUDIT
# =============================================================================

main() {
    echo -e "${BLUE}=== GeuseMaker Security Audit ===${NC}"
    echo "Starting comprehensive security check..."
    echo
    
    local total_issues=0
    local exit_code=0
    
    # Run all audit functions
    audit_secrets || ((total_issues += $?))
    echo
    
    audit_docker_security || ((total_issues += $?))
    echo
    
    audit_file_permissions || ((total_issues += $?))
    echo
    
    audit_aws_config || ((total_issues += $?))
    echo
    
    audit_network_security || ((total_issues += $?))
    echo
    
    audit_dependencies || ((total_issues += $?))
    echo
    
    # Final summary
    echo -e "${BLUE}=== Security Audit Summary ===${NC}"
    if [[ $total_issues -eq 0 ]]; then
        echo -e "${GREEN}✓ Security audit passed with no critical issues${NC}"
        exit_code=0
    elif [[ $total_issues -lt 5 ]]; then
        echo -e "${YELLOW}⚠ Security audit completed with $total_issues minor issues${NC}"
        echo "Review the issues above and fix before production deployment"
        exit_code=1
    else
        echo -e "${RED}✗ Security audit failed with $total_issues issues${NC}"
        echo "Fix critical security issues before deployment"
        exit_code=2
    fi
    
    echo
    echo "Security audit completed. Review all findings above."
    
    exit $exit_code
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi