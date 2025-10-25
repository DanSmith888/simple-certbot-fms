#!/bin/bash

# FileMaker Server Certificate Manager
# Unified script for Let's Encrypt certificate management with DigitalOcean DNS
# Supports both certificate requests and renewals

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="fms-cert-manager"
SCRIPT_AUTHOR="Daniel Smith"
SCRIPT_GITHUB="https://github.com/DanSmith888/simple-certbot-fms"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEBUG=false
FORCE_RENEW=false
IMPORT_CERT=false
RESTART_FMS=false
SANDBOX=true
LIVE=false

# Check if running on Ubuntu 24.04 LTS or above
check_ubuntu() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            error_exit "This script only supports Ubuntu"
        fi
        
        # Check if version is 24.04 or above
        if [[ "$VERSION_ID" < "24.04" ]]; then
            error_exit "This script requires Ubuntu 24.04 LTS or above"
        fi
    else
        error_exit "Cannot detect operating system"
    fi
}

# FileMaker Server paths (Ubuntu only)
FMS_CERTBOT_PATH="/opt/FileMaker/FileMaker Server/CStore/Certbot"
FMS_LOG_PATH="/opt/FileMaker/FileMaker Server/CStore/Certbot/logs"

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$FMS_LOG_PATH/cert-manager.log"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    log "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "SUCCESS" "$@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    log "ERROR" "$@"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    log "WARN" "$@"
}

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
        log "DEBUG" "$@"
    fi
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root or with sudo"
    fi
}

# Check required dependencies
check_dependencies() {
    log_info "Checking system dependencies..."
    
    # Check certbot
    if ! command -v certbot &> /dev/null; then
        error_exit "Certbot is not installed. Please run: sudo apt install certbot"
    fi
    
    # Check DigitalOcean plugin
    if ! certbot plugins | grep -q dns-digitalocean; then
        error_exit "DigitalOcean DNS plugin is not installed. Please run: sudo apt install python3-certbot-dns-digitalocean"
    fi
    
    # Check fmsadmin
    if ! command -v fmsadmin &> /dev/null; then
        error_exit "fmsadmin is not available. Please ensure FileMaker Server is installed"
    fi
    
    log_success "All dependencies are available"
}

# Create necessary directories
setup_directories() {
    # Create certbot directory
    mkdir -p "$FMS_CERTBOT_PATH"
    
    # Create logs directory
    mkdir -p "$FMS_LOG_PATH"
    
    # Set proper ownership
    if id "fmserver" &>/dev/null; then
        chown -R fmserver:fmsadmin "$FMS_CERTBOT_PATH" 2>/dev/null || true
    fi
}

# Setup DigitalOcean credentials (temporary)
setup_do_credentials() {
    log_info "Setting up DigitalOcean credentials..."
    
    local do_ini="/etc/certbot/digitalocean.ini"
    
    # Create certbot directory if it doesn't exist
    mkdir -p "/etc/certbot"
    
    # Create credentials file
    cat > "$do_ini" << EOF
dns_digitalocean_token = $DO_TOKEN
EOF
    
    # Set secure permissions
    chmod 600 "$do_ini"
    
    log_success "DigitalOcean credentials configured"
}

# Cleanup DigitalOcean credentials
cleanup_do_credentials() {
    log_info "Cleaning up DigitalOcean credentials..."
    
    local do_ini="/etc/certbot/digitalocean.ini"
    
    # Remove credentials file
    if [[ -f "$do_ini" ]]; then
        rm -f "$do_ini"
        log_success "DigitalOcean credentials cleaned up"
    fi
}

# State management functions
get_state_file() {
    local hostname="$1"
    echo "$FMS_CERTBOT_PATH/state_${hostname}.json"
}

# Read state from file
read_state() {
    local hostname="$1"
    local state_file=$(get_state_file "$hostname")
    
    if [[ -f "$state_file" ]]; then
        # Read state from JSON file
        STATE_HOSTNAME=$(jq -r '.hostname' "$state_file" 2>/dev/null || echo "")
        STATE_SANDBOX=$(jq -r '.sandbox' "$state_file" 2>/dev/null || echo "false")
        STATE_EMAIL=$(jq -r '.email' "$state_file" 2>/dev/null || echo "")
        STATE_LAST_RUN=$(jq -r '.last_run' "$state_file" 2>/dev/null || echo "")
        STATE_CERT_EXISTS=$(jq -r '.cert_exists' "$state_file" 2>/dev/null || echo "false")
    else
        # No state file exists
        STATE_HOSTNAME=""
        STATE_SANDBOX="false"
        STATE_EMAIL=""
        STATE_LAST_RUN=""
        STATE_CERT_EXISTS="false"
    fi
}

# Write state to file
write_state() {
    local hostname="$1"
    local email="$2"
    local sandbox="$3"
    local cert_exists="$4"
    local state_file=$(get_state_file "$hostname")
    
    # Create state JSON
    cat > "$state_file" << EOF
{
    "hostname": "$hostname",
    "email": "$email",
    "sandbox": "$sandbox",
    "last_run": "$(date -Iseconds)",
    "cert_exists": "$cert_exists"
}
EOF
    
    # Set proper permissions
    chmod 600 "$state_file"
    if id "fmserver" &>/dev/null; then
        chown fmserver:fmsadmin "$state_file" 2>/dev/null || true
    fi
    
    log_debug "State written to $state_file"
}

# Check if certificate exists
certificate_exists() {
    local hostname="$1"
    local cert_path="$FMS_CERTBOT_PATH/live/$hostname"
    
    if [[ -d "$cert_path" ]] && [[ -f "$cert_path/fullchain.pem" ]] && [[ -f "$cert_path/privkey.pem" ]]; then
        return 0
    else
        return 1
    fi
}

# Get certificate expiry info
get_cert_expiry() {
    local hostname="$1"
    local cert_file="$FMS_CERTBOT_PATH/live/$hostname/fullchain.pem"
    
    if [[ -f "$cert_file" ]]; then
        openssl x509 -in "$cert_file" -noout -dates | grep "notAfter" | cut -d= -f2
    else
        echo ""
    fi
}

# Check if certificate needs renewal
cert_needs_renewal() {
    local hostname="$1"
    local expiry_date=$(get_cert_expiry "$hostname")
    
    if [[ -z "$expiry_date" ]]; then
        return 1
    fi
    
    # Check if certificate expires within 30 days
    local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
    local current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    log_debug "Certificate expires in $days_until_expiry days"
    
    if [[ $days_until_expiry -lt 30 ]]; then
        return 0
    else
        return 1
    fi
}

# Request new certificate
request_certificate() {
    local hostname="$1"
    local email="$2"
    
    log_info "Requesting new certificate for $hostname"
    
    # Build certbot command
    local certbot_cmd="certbot certonly"
    certbot_cmd="$certbot_cmd --dns-digitalocean"
    certbot_cmd="$certbot_cmd --dns-digitalocean-credentials /etc/certbot/digitalocean.ini"
    certbot_cmd="$certbot_cmd --agree-tos --non-interactive"
    certbot_cmd="$certbot_cmd --no-auto-renew"
    certbot_cmd="$certbot_cmd --email $email"
    certbot_cmd="$certbot_cmd -d $hostname"
    certbot_cmd="$certbot_cmd --config-dir \"$FMS_CERTBOT_PATH\""
    certbot_cmd="$certbot_cmd --work-dir \"$FMS_CERTBOT_PATH\""
    certbot_cmd="$certbot_cmd --logs-dir \"$FMS_LOG_PATH\""
    
    # Add staging flag if sandbox mode (default)
    if [[ "$LIVE" != "true" ]]; then
        certbot_cmd="$certbot_cmd --staging"
        log_info "Using Let's Encrypt staging environment add --live to use production environment"
    else
        log_info "Using Let's Encrypt production environment"
    fi
    
    # Execute certbot
    log_debug "Running: $certbot_cmd"
    if eval "$certbot_cmd"; then
        log_success "Certificate requested successfully"
        return 0
    else
        log_error "Certificate request failed"
        return 1
    fi
}

# Renew existing certificate
renew_certificate() {
    local hostname="$1"
    
    log_info "Renewing certificate for $hostname"
    
    # Build certbot command
    local certbot_cmd="certbot renew"
    certbot_cmd="$certbot_cmd --dns-digitalocean"
    certbot_cmd="$certbot_cmd --dns-digitalocean-credentials /etc/certbot/digitalocean.ini"
    certbot_cmd="$certbot_cmd --cert-name $hostname"
    certbot_cmd="$certbot_cmd --no-auto-renew"
    certbot_cmd="$certbot_cmd --config-dir \"$FMS_CERTBOT_PATH\""
    certbot_cmd="$certbot_cmd --work-dir \"$FMS_CERTBOT_PATH\""
    certbot_cmd="$certbot_cmd --logs-dir \"$FMS_LOG_PATH\""
    
    # Add force renewal if requested
    if [[ "$FORCE_RENEW" == "true" ]]; then
        certbot_cmd="$certbot_cmd --force-renewal"
        log_info "Force renewal requested"
    fi
    
    # Add staging flag if sandbox mode (default)
    if [[ "$LIVE" != "true" ]]; then
        certbot_cmd="$certbot_cmd --staging"
    fi
    
    # Execute certbot
    log_debug "Running: $certbot_cmd"
    if eval "$certbot_cmd"; then
        log_success "Certificate renewed successfully"
        return 0
    else
        log_error "Certificate renewal failed"
        return 1
    fi
}

# Import certificate to FileMaker Server
import_certificate() {
    local hostname="$1"
    
    if [[ "$IMPORT_CERT" != "true" ]]; then
        log_info "Certificate import skipped (--import-cert=false)"
        return 0
    fi
    
    log_info "Importing certificate to FileMaker Server"
    
    local cert_file="$FMS_CERTBOT_PATH/live/$hostname/fullchain.pem"
    local key_file="$FMS_CERTBOT_PATH/live/$hostname/privkey.pem"
    
    # Verify files exist
    if [[ ! -f "$cert_file" ]] || [[ ! -f "$key_file" ]]; then
        error_exit "Certificate files not found: $cert_file, $key_file"
    fi
    
    # Set proper ownership
    chown fmserver:fmsadmin "$cert_file" "$key_file"
    
    # Import certificate
    if fmsadmin certificate import "$cert_file" --keyfile "$key_file" -y -u "$FMS_USERNAME" -p "$FMS_PASSWORD" >> "$FMS_LOG_PATH/fms-import.log" 2>&1; then
        log_success "Certificate imported successfully"
        return 0
    else
        log_error "Certificate import failed. Check $FMS_LOG_PATH/fms-import.log"
        return 1
    fi
}

# Restart FileMaker Server
restart_filemaker_server() {
    if [[ "$RESTART_FMS" != "true" ]]; then
        log_info "FileMaker Server restart skipped (--restart-fms=false)"
        return 0
    fi
    
    if [[ "$IMPORT_CERT" != "true" ]]; then
        log_info "FileMaker Server restart skipped (no certificate import performed)"
        return 0
    fi
    
    log_info "Restarting FileMaker Server..."
    
    # Stop FileMaker Server
    systemctl stop fmshelper
    
    # Wait for service to stop
    sleep 10
    
    # Start FileMaker Server
    systemctl start fmshelper
    
    log_success "FileMaker Server restarted"
}

# Display version information
show_version() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Author: $SCRIPT_AUTHOR
GitHub: $SCRIPT_GITHUB

A unified script for Let's Encrypt certificate management with DigitalOcean DNS
for FileMaker Server. Supports both certificate requests and renewals with
semi-intelligent state management.

EOF
}

# Display usage information
usage() {
    cat << EOF
FileMaker Server Certificate Manager v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

REQUIRED OPTIONS:
    --hostname HOSTNAME     Domain name for the certificate
    --email EMAIL          Email for Let's Encrypt notifications
    --do-token TOKEN        DigitalOcean API token
    --fms-username USER     FileMaker Admin Console username
    --fms-password PASS     FileMaker Admin Console password


OPTIONAL OPTIONS:
    --live                  Use Let's Encrypt production environment (default: staging)
    --force-renew           Force renewal even if not needed
    --import-cert           Import certificate to FileMaker Server (default: false)
    --restart-fms           Restart FileMaker Server after import (default: false)
    --debug                 Enable debug logging
    --version, -v            Show version information

EXAMPLES:
    # Request new certificate (staging by default)
    $0 --hostname example.com --email admin@example.com --do-token dop_v1_xxx --fms-username admin --fms-password password

    # Production certificate
    $0 --hostname example.com --email admin@example.com --do-token dop_v1_xxx --fms-username admin --fms-password password --live

    # Renew existing certificate
    $0 --hostname example.com --email admin@example.com --do-token dop_v1_xxx --fms-username admin --fms-password password --live

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --hostname)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --email)
                EMAIL="$2"
                shift 2
                ;;
            --do-token)
                DO_TOKEN="$2"
                shift 2
                ;;
            --live)
                LIVE=true
                shift
                ;;
            --force-renew)
                FORCE_RENEW=true
                shift
                ;;
            --import-cert)
                IMPORT_CERT=true
                shift
                ;;
            --restart-fms)
                RESTART_FMS=true
                shift
                ;;
            --fms-username)
                FMS_USERNAME="$2"
                shift 2
                ;;
            --fms-password)
                FMS_PASSWORD="$2"
                shift 2
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Validate required parameters
validate_parameters() {
    local errors=()
    
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        errors+=("--hostname is required")
    fi
    
    if [[ -z "${EMAIL:-}" ]]; then
        errors+=("--email is required")
    fi
    
    if [[ -z "${DO_TOKEN:-}" ]]; then
        errors+=("--do-token is required")
    fi
    
    # No validation needed - sandbox is default, --live overrides it
    
    if [[ -z "${FMS_USERNAME:-}" ]]; then
        errors+=("--fms-username is required")
    fi
    
    if [[ -z "${FMS_PASSWORD:-}" ]]; then
        errors+=("--fms-password is required")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            log_error "$error"
        done
        error_exit "Parameter validation failed"
    fi
}

# Main execution
main() {
    # Setup directories first (before any logging)
    setup_directories
    
    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log_debug "Debug mode: $DEBUG"
    log_info "Hostname: $DOMAIN_NAME"
    log_info "Email: $EMAIL"
    log_info "Environment: $([ "$LIVE" == "true" ] && echo "production" || echo "staging")"
    
    # Check prerequisites
    check_root
    check_ubuntu
    check_dependencies
    setup_do_credentials
    
    # Read previous state
    read_state "$DOMAIN_NAME"
    log_debug "Previous state - Hostname: $STATE_HOSTNAME, Sandbox: $STATE_SANDBOX, Cert exists: $STATE_CERT_EXISTS"
    
    # Determine action based on state
    local action="request"
    local state_changed=false
    
    # Check if this is a different hostname
    if [[ "$STATE_HOSTNAME" != "$DOMAIN_NAME" ]] && [[ -n "$STATE_HOSTNAME" ]]; then
        log_info "Different hostname detected. Previous: $STATE_HOSTNAME, Current: $DOMAIN_NAME"
        state_changed=true
    fi
    
    # Check if environment changed (sandbox vs live)
    local current_sandbox=$([ "$LIVE" == "true" ] && echo "false" || echo "true")
    if [[ "$STATE_SANDBOX" != "$current_sandbox" ]]; then
        log_info "Environment changed. Previous: $([ "$STATE_SANDBOX" == "true" ] && echo "staging" || echo "production"), Current: $([ "$current_sandbox" == "true" ] && echo "staging" || echo "production")"
        state_changed=true
    fi
    
    # Determine action
    if [[ "$state_changed" == "true" ]]; then
        action="request"
        log_info "State changed - requesting new certificate"
    elif certificate_exists "$DOMAIN_NAME"; then
        if cert_needs_renewal "$DOMAIN_NAME"; then
            action="renew"
            log_info "Certificate exists but needs renewal"
        else
            log_info "Certificate exists and is valid"
            # Update state with current status
            write_state "$DOMAIN_NAME" "$EMAIL" "$current_sandbox" "true"
            cleanup_do_credentials
            exit 0
        fi
    else
        action="request"
        log_info "No certificate found - requesting new certificate"
    fi
    
    # Execute action
    case "$action" in
        "request")
            if request_certificate "$DOMAIN_NAME" "$EMAIL"; then
                if import_certificate "$DOMAIN_NAME"; then
                    restart_filemaker_server
                    # Update state after successful request
                    write_state "$DOMAIN_NAME" "$EMAIL" "$current_sandbox" "true"
                    log_success "Certificate request completed successfully"
                    cleanup_do_credentials
                    exit 0
                else
                    cleanup_do_credentials
                    error_exit "Certificate import failed"
                fi
            else
                cleanup_do_credentials
                error_exit "Certificate request failed"
            fi
            ;;
        "renew")
            if renew_certificate "$DOMAIN_NAME"; then
                if import_certificate "$DOMAIN_NAME"; then
                    restart_filemaker_server
                    # Update state after successful renewal
                    write_state "$DOMAIN_NAME" "$EMAIL" "$current_sandbox" "true"
                    log_success "Certificate renewal completed successfully"
                    cleanup_do_credentials
                    exit 0
                else
                    cleanup_do_credentials
                    error_exit "Certificate import failed"
                fi
            else
                cleanup_do_credentials
                error_exit "Certificate renewal failed"
            fi
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    validate_parameters
    main
fi
