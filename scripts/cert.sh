#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# Source shared utilities
source "$(dirname "$0")/utils.sh"

CERTS_DIR="$HOME/.certs"

DEV_CERTS_DIR="$CERTS_DIR/dev"
DEV_CA_CERT="$DEV_CERTS_DIR/rootCA.pem"
DEV_CA_KEY="$DEV_CERTS_DIR/rootCA-key.pem"
DEV_CERT="$DEV_CERTS_DIR/cert.pem"
DEV_KEY="$DEV_CERTS_DIR/key.pem"

# Folder where mkcert will place and look for the local CA files.
export CAROOT="$DEV_CERTS_DIR"

DEV_DOMAIN_1ST="localhost"
DEV_DOMAIN_2ND="dev"
DEV_DOMAIN="$DEV_DOMAIN_2ND.$DEV_DOMAIN_1ST"

# Check if mkcert installed
is_mkcert_installed() {
    command_exists mkcert
    return $?
}

# Check if nss installed
is_nss_installed() {
    command_exists nss
    return $?
}


# Check prerequisites
check_prerequisites() {
    # mkcert
    if ! is_mkcert_installed; then
        log_error "mkcert is not installed: https://github.com/FiloSottile/mkcert?tab=readme-ov-file#installation"
        exit "$EXIT_ERROR"
    fi
    # nss
    # if ! is_nss_installed; then
    #     log_error "nss is not installed: https://github.com/FiloSottile/mkcert?tab=readme-ov-file#installation"
    #     exit "$EXIT_ERROR"
    # fi
    return "$EXIT_SUCCESS"
}

# Check prerequisites
check_prerequisites

# Create certs directory if it doesn't exist
if ensure_directory_exists "$DEV_CERTS_DIR"; then
    log_info "Created certificates directory: ${CERTS_DIR}"
fi



mkcert -key-file "$DEV_KEY" -cert-file "$DEV_CERT" "$DEV_DOMAIN" "*.$DEV_DOMAIN" localhost 127.0.0.1 ::1
log_info "Created certs for *.$DEV_DOMAIN"
log_info "Certificate: ${DEV_CERT}"
log_info "Key: ${DEV_KEY}"