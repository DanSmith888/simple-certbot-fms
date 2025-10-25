#!/bin/bash

# FileMaker Server Certificate Manager - One-Line Installer
# Interactive installation script with automatic schedule creation

set -euo pipefail

# Script metadata
INSTALLER_VERSION="1.0.0"
SCRIPT_NAME="fms-cert-manager-installer"
SCRIPT_AUTHOR="Daniel Smith"
SCRIPT_GITHUB="https://github.com/DanSmith888/simple-certbot-fms"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default values
DEBUG=false
AUTO_CONFIRM=false
FMS_HOST="localhost"
FMS_PORT="16000"
FMS_USERNAME=""
FMS_PASSWORD=""
DOMAIN_NAME=""
EMAIL=""
DNS_PROVIDER="digitalocean"
DO_TOKEN=""
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
USE_LIVE=false
IMPORT_CERT=true
RESTART_FMS=true
SCHEDULE_NAME="SSL Certificate Renewal"
SCHEDULE_FREQUENCY="12"  # hours

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_prompt() {
    echo -e "${CYAN}[PROMPT]${NC} $*"
}

log_header() {
    echo -e "${BOLD}${CYAN}$*${NC}"
}

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
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
        log_error "This installer must be run as root or with sudo"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

# Check if running on Ubuntu 24.04 LTS or above
check_ubuntu() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            error_exit "This script only supports Ubuntu (detected: $PRETTY_NAME)"
        fi
        
        # Check if version is 24.04 or above
        if [[ "$VERSION_ID" < "24.04" ]]; then
            error_exit "This script requires Ubuntu 24.04 LTS or above (detected: $PRETTY_NAME)"
        fi
    else
        error_exit "Cannot detect operating system"
    fi
    
    log_success "Detected OS: $PRETTY_NAME"
}

# Check if FileMaker Server is installed
check_filemaker_server() {
    log_info "Checking for FileMaker Server installation..."
    
    if ! command -v fmsadmin &> /dev/null; then
        error_exit "FileMaker Server is not installed or fmsadmin is not available"
    fi
    
    if [[ ! -d "/opt/FileMaker/FileMaker Server" ]]; then
        error_exit "FileMaker Server directory not found at /opt/FileMaker/FileMaker Server"
    fi
    
    log_success "FileMaker Server is installed"
}

# Display welcome banner
show_banner() {
    clear
    log_header "=============================================="
    log_header "FileMaker Server Certificate Manager Installer"
    log_header "=============================================="
    echo
    log_info "This installer will:"
    echo "  • Install required packages (certbot, DigitalOcean plugin, etc.)"
    echo "  • Download and configure the certificate manager script"
    echo "  • Prompt you for configuration details"
    echo "  • Create an automated schedule in FileMaker Server"
    echo
    log_warn "Requirements:"
    echo "  • Ubuntu 24.04 LTS or above"
    echo "  • FileMaker Server 2024 or later"
    echo "  • DigitalOcean account with DNS management"
    echo "  • Domain configured in DigitalOcean DNS"
    echo
}

# Interactive prompts for configuration
prompt_configuration() {
    log_header "Configuration Setup"
    echo
    
    # Domain name
    while [[ -z "$DOMAIN_NAME" ]]; do
        log_prompt "Enter your domain name (e.g., example.com):"
        read -r DOMAIN_NAME
        if [[ -z "$DOMAIN_NAME" ]]; then
            log_error "Domain name is required"
        fi
    done
    
    # Email
    while [[ -z "$EMAIL" ]]; do
        log_prompt "Enter your email address for Let's Encrypt notifications:"
        read -r EMAIL
        if [[ -z "$EMAIL" ]]; then
            log_error "Email address is required"
        elif [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            log_error "Please enter a valid email address"
            EMAIL=""
        fi
    done
    
    # DNS Provider selection
    log_prompt "Choose your DNS provider:"
    echo "1) DigitalOcean"
    echo "2) AWS Route53"
    log_prompt "Enter choice (1 or 2, default: 1):"
    read -r dns_choice
    
    case "$dns_choice" in
        "2")
            DNS_PROVIDER="route53"
            log_info "Selected Route53 DNS provider"
            ;;
        *)
            DNS_PROVIDER="digitalocean"
            log_info "Selected DigitalOcean DNS provider"
            ;;
    esac
    
    # DNS Provider credentials
    case "$DNS_PROVIDER" in
        "digitalocean")
            while [[ -z "$DO_TOKEN" ]]; do
                log_prompt "Enter your DigitalOcean API token:"
                read -r DO_TOKEN
                if [[ -z "$DO_TOKEN" ]]; then
                    log_error "DigitalOcean API token is required"
                elif [[ ! "$DO_TOKEN" =~ ^dop_v1_ ]]; then
                    log_warn "Token doesn't start with 'dop_v1_' - please verify it's correct"
                    log_prompt "Continue anyway? (y/N):"
                    read -r confirm
                    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                        DO_TOKEN=""
                    fi
                fi
            done
            ;;
        "route53")
            while [[ -z "$AWS_ACCESS_KEY_ID" ]]; do
                log_prompt "Enter your AWS Access Key ID:"
                read -r AWS_ACCESS_KEY_ID
                if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
                    log_error "AWS Access Key ID is required"
                fi
            done
            
            while [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; do
                log_prompt "Enter your AWS Secret Access Key:"
                read -rs AWS_SECRET_ACCESS_KEY
                echo
                if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
                    log_error "AWS Secret Access Key is required"
                fi
            done
            ;;
    esac
    
    # FileMaker Server details
    log_prompt "Enter FileMaker Server hostname (default: localhost):"
    read -r input
    if [[ -n "$input" ]]; then
        FMS_HOST="$input"
    fi
    
    log_prompt "Enter FileMaker Server port (default: 16000):"
    read -r input
    if [[ -n "$input" ]]; then
        FMS_PORT="$input"
    fi
    
    while [[ -z "$FMS_USERNAME" ]]; do
        log_prompt "Enter FileMaker Server Admin Console username:"
        read -r FMS_USERNAME
        if [[ -z "$FMS_USERNAME" ]]; then
            log_error "FileMaker Server username is required"
        fi
    done
    
    while [[ -z "$FMS_PASSWORD" ]]; do
        log_prompt "Enter FileMaker Server Admin Console password:"
        read -rs FMS_PASSWORD
        echo
        if [[ -z "$FMS_PASSWORD" ]]; then
            log_error "FileMaker Server password is required"
        fi
    done
    
    # Environment choice
    log_prompt "Use Let's Encrypt production environment? (y/N):"
    read -r use_live
    if [[ "$use_live" =~ ^[Yy]$ ]]; then
        USE_LIVE=true
        log_warn "Using PRODUCTION environment - certificates will be real"
    else
        log_info "Using STAGING environment - certificates will be test certificates"
    fi
    
    # Import and restart options
    log_prompt "Import certificate to FileMaker Server? (Y/n):"
    read -r import_choice
    if [[ "$import_choice" =~ ^[Nn]$ ]]; then
        IMPORT_CERT=false
    fi
    
    if [[ "$IMPORT_CERT" == "true" ]]; then
        log_prompt "Restart FileMaker Server after certificate import? (Y/n):"
        read -r restart_choice
        if [[ "$restart_choice" =~ ^[Nn]$ ]]; then
            RESTART_FMS=false
        fi
    fi
    
    # Schedule frequency
    log_prompt "How often should the script run? (hours, default: 12):"
    read -r input
    if [[ -n "$input" ]] && [[ "$input" =~ ^[0-9]+$ ]]; then
        SCHEDULE_FREQUENCY="$input"
    fi
    
    echo
    log_header "Configuration Summary"
    echo "  Domain: $DOMAIN_NAME"
    echo "  Email: $EMAIL"
    echo "  DNS Provider: $DNS_PROVIDER"
    case "$DNS_PROVIDER" in
        "digitalocean")
            echo "  DigitalOcean Token: ${DO_TOKEN:0:10}..."
            ;;
        "route53")
            echo "  AWS Access Key: ${AWS_ACCESS_KEY_ID:0:10}..."
            echo "  AWS Secret Key: ${AWS_SECRET_ACCESS_KEY:0:10}..."
            ;;
    esac
    echo "  FileMaker Server: $FMS_HOST:$FMS_PORT"
    echo "  Username: $FMS_USERNAME"
    echo "  Environment: $([ "$USE_LIVE" == "true" ] && echo "Production" || echo "Staging")"
    echo "  Import Certificate: $([ "$IMPORT_CERT" == "true" ] && echo "Yes" || echo "No")"
    echo "  Restart FMS: $([ "$RESTART_FMS" == "true" ] && echo "Yes" || echo "No")"
    echo "  Schedule Frequency: Every $SCHEDULE_FREQUENCY hours"
    echo
    
    log_prompt "Continue with installation? (Y/n):"
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
}

# Install required packages
install_packages() {
    log_info "Installing required packages..."
    
    # Update package list
    log_info "Updating package list..."
    apt update -y
    
    # Install base packages
    log_info "Installing certbot and dependencies..."
    apt install -y certbot curl openssl jq
    
    # Install DNS provider specific packages
    case "$DNS_PROVIDER" in
        "digitalocean")
            log_info "Installing DigitalOcean DNS plugin..."
            apt install -y python3-certbot-dns-digitalocean
            ;;
        "route53")
            log_info "Installing Route53 DNS plugin..."
            apt install -y python3-certbot-dns-route53
            ;;
    esac
    
    log_success "Packages installed successfully"
}

# Download and setup certificate manager script
setup_certificate_manager() {
    log_info "Setting up certificate manager script..."
    
    # Create FileMaker Server scripts directory if it doesn't exist
    local scripts_dir="/opt/FileMaker/FileMaker Server/Data/Scripts"
    mkdir -p "$scripts_dir"
    
    # Download the certificate manager script
    local script_url="https://raw.githubusercontent.com/DanSmith888/simple-certbot-fms/main/fms-cert-manager.sh"
    local script_path="$scripts_dir/fms-cert-manager.sh"
    
    log_info "Downloading certificate manager script..."
    if curl -fsSL "$script_url" -o "$script_path"; then
        log_success "Certificate manager script downloaded"
    else
        error_exit "Failed to download certificate manager script"
    fi
    
    # Set proper permissions
    chmod +x "$script_path"
    chown fmserver:fmsadmin "$script_path"
    
    log_success "Certificate manager script configured"
}

# Test FileMaker Server connection
test_fms_connection() {
    log_info "Testing FileMaker Server connection..."
    
    # Test connection using fmsadmin
    if fmsadmin -u "$FMS_USERNAME" -p "$FMS_PASSWORD" -h "$FMS_HOST" -p "$FMS_PORT" list 2>/dev/null; then
        log_success "FileMaker Server connection successful"
    else
        log_error "Failed to connect to FileMaker Server"
        log_error "Please verify your credentials and server details"
        return 1
    fi
}

# Create schedule in FileMaker Server using Admin API
create_schedule() {
    log_info "Creating automated schedule in FileMaker Server..."
    
    # Build the script parameters
    local script_params="--hostname $DOMAIN_NAME --email $EMAIL --fms-username $FMS_USERNAME --fms-password $FMS_PASSWORD --dns-provider $DNS_PROVIDER"
    
    # Add DNS provider specific parameters
    case "$DNS_PROVIDER" in
        "digitalocean")
            script_params="$script_params --do-token $DO_TOKEN"
            ;;
        "route53")
            script_params="$script_params --aws-access-key-id $AWS_ACCESS_KEY_ID --aws-secret-key $AWS_SECRET_ACCESS_KEY"
            ;;
    esac
    
    if [[ "$USE_LIVE" == "true" ]]; then
        script_params="$script_params --live"
    fi
    
    if [[ "$IMPORT_CERT" == "true" ]]; then
        script_params="$script_params --import-cert"
    fi
    
    if [[ "$RESTART_FMS" == "true" ]]; then
        script_params="$script_params --restart-fms"
    fi
    
    # Create the schedule using fmsadmin
    local schedule_script="fms-cert-manager.sh $script_params"
    
    log_info "Creating schedule: $SCHEDULE_NAME"
    log_info "Script: $schedule_script"
    log_info "Frequency: Every $SCHEDULE_FREQUENCY hours"
    
    # Try using fmsadmin first
    if fmsadmin -u "$FMS_USERNAME" -p "$FMS_PASSWORD" -h "$FMS_HOST" -p "$FMS_PORT" \
        schedule create \
        --name "$SCHEDULE_NAME" \
        --script "$schedule_script" \
        --frequency "$SCHEDULE_FREQUENCY" \
        --enabled 2>/dev/null; then
        log_success "Schedule created successfully using fmsadmin"
    else
        # Fallback to manual instructions
        log_warn "Failed to create schedule automatically using fmsadmin"
        log_info "Creating schedule manually via FileMaker Server Admin API..."
        
        # Create schedule using FileMaker Server Admin API
        create_schedule_via_api
    fi
}

# Create schedule using FileMaker Server Admin API
create_schedule_via_api() {
    local api_url="https://$FMS_HOST:$FMS_PORT/fmi/admin/api/v2/schedule"
    local auth_header=$(echo -n "$FMS_USERNAME:$FMS_PASSWORD" | base64)
    
    # Calculate next run time (1 hour from now)
    local next_run=$(date -d "+1 hour" -Iseconds)
    
    # Create JSON payload for the schedule
    local json_payload=$(cat << EOF
{
    "name": "$SCHEDULE_NAME",
    "script": "$schedule_script",
    "enabled": true,
    "frequency": "hourly",
    "interval": $SCHEDULE_FREQUENCY,
    "nextRun": "$next_run",
    "user": "root"
}
EOF
)
    
    log_info "Sending POST request to FileMaker Server Admin API..."
    log_info "URL: $api_url"
    
    # Make the API request
    local response=$(curl -s -k -X POST \
        -H "Authorization: Basic $auth_header" \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        "$api_url" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        log_success "Schedule created successfully via Admin API"
        log_debug "API Response: $response"
    else
        log_warn "Failed to create schedule via Admin API"
        log_info "Manual setup required - see instructions below"
        show_manual_schedule_instructions
    fi
}

# Show manual schedule creation instructions
show_manual_schedule_instructions() {
    log_info "Manual Schedule Creation Instructions:"
    echo
    echo "1. Open FileMaker Server Admin Console:"
    echo "   https://$FMS_HOST:$FMS_PORT/admin-console"
    echo
    echo "2. Go to Configuration → Schedules → Create Schedules → New System Script"
    echo
    echo "3. Configure the schedule:"
    echo "   • Name: $SCHEDULE_NAME"
    echo "   • Script Path: fms-cert-manager.sh"
    echo "   • Parameters: $script_params"
    echo "   • User: root"
    echo "   • Frequency: Every $SCHEDULE_FREQUENCY hours"
    echo "   • Enabled: Yes"
    echo
    echo "4. Save the schedule"
    echo
}

# Run initial certificate request
run_initial_certificate() {
    log_info "Running initial certificate request..."
    
    # Build the command
    local script_path="/opt/FileMaker/FileMaker Server/Data/Scripts/fms-cert-manager.sh"
    local cmd="$script_path --hostname $DOMAIN_NAME --email $EMAIL --fms-username $FMS_USERNAME --fms-password $FMS_PASSWORD --dns-provider $DNS_PROVIDER"
    
    # Add DNS provider specific parameters
    case "$DNS_PROVIDER" in
        "digitalocean")
            cmd="$cmd --do-token $DO_TOKEN"
            ;;
        "route53")
            cmd="$cmd --aws-access-key-id $AWS_ACCESS_KEY_ID --aws-secret-key $AWS_SECRET_ACCESS_KEY"
            ;;
    esac
    
    if [[ "$USE_LIVE" == "true" ]]; then
        cmd="$cmd --live"
    fi
    
    if [[ "$IMPORT_CERT" == "true" ]]; then
        cmd="$cmd --import-cert"
    fi
    
    if [[ "$RESTART_FMS" == "true" ]]; then
        cmd="$cmd --restart-fms"
    fi
    
    log_info "Executing: $cmd"
    
    if eval "$cmd"; then
        log_success "Initial certificate request completed successfully"
    else
        log_warn "Initial certificate request failed"
        log_info "You can run the script manually later to troubleshoot"
    fi
}

# Display completion message
show_completion() {
    log_header "Installation Complete!"
    echo
    log_success "FileMaker Server Certificate Manager has been installed and configured"
    echo
    log_info "What was installed:"
    echo "  • Required packages (certbot, DigitalOcean plugin, etc.)"
    echo "  • Certificate manager script at: /opt/FileMaker/FileMaker Server/Data/Scripts/fms-cert-manager.sh"
    echo "  • Automated schedule: $SCHEDULE_NAME"
    echo
    log_info "Configuration:"
    echo "  • Domain: $DOMAIN_NAME"
    echo "  • Environment: $([ "$USE_LIVE" == "true" ] && echo "Production" || echo "Staging")"
    echo "  • Schedule: Every $SCHEDULE_FREQUENCY hours"
    echo
    log_info "Next steps:"
    echo "  1. Verify your domain is configured in DigitalOcean DNS"
    echo "  2. Check the schedule in FileMaker Server Admin Console"
    echo "  3. Monitor logs at: /opt/FileMaker/FileMaker Server/CStore/Certbot/logs/"
    echo
    if [[ "$USE_LIVE" != "true" ]]; then
        log_warn "Remember: You're using staging environment for testing"
        log_info "Once everything works, you can switch to production by editing the schedule"
    fi
    echo
    log_success "Installation completed successfully!"
}

# Main execution
main() {
    show_banner
    check_root
    check_ubuntu
    check_filemaker_server
    prompt_configuration
    install_packages
    setup_certificate_manager
    
    if test_fms_connection; then
        create_schedule
        run_initial_certificate
    else
        log_warn "Skipping schedule creation and initial certificate request"
        log_info "You can run the script manually after fixing the connection"
    fi
    
    show_completion
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
