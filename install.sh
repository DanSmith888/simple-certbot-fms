#!/bin/bash

# FileMaker Server Certificate Manager Installer
# Installs the certificate manager script and dependencies for Let's Encrypt DNS challenge
# Supports DigitalOcean, AWS Route53, and Linode DNS providers

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="FileMaker Server Certificate Manager Installer"
SCRIPT_AUTHOR="Daniel Smith"
SCRIPT_GITHUB="https://github.com/DanSmith888/simple-certificate-manager"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions with full line coloring
log_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

log_step() {
    echo -e "${CYAN}[STEP] $1${NC}"
}

log_prompt() {
    echo -e "${BOLD}[PROMPT] $1${NC}"
}

# Display welcome message
show_welcome() {
    clear
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo -e "${BOLD}${CYAN}  FileMaker Server Certificate Manager  ${NC}"
    echo -e "${BOLD}${CYAN}           Installer v$SCRIPT_VERSION           ${NC}"
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo
    echo -e "${BOLD}What this script does:${NC}"
    echo "• Installs Let's Encrypt certificate management for FileMaker Server"
    echo "• Sets up DNS challenge support for DigitalOcean, AWS Route53, or Linode"
    echo "• Downloads and configures the certificate manager script"
    echo "• Installs all required dependencies"
    echo
    echo -e "${BOLD}How to use:${NC}"
    echo "curl -sSL https://raw.githubusercontent.com/DanSmith888/simple-certificate-manager/main/install.sh | sudo bash"
    echo
    echo -e "${YELLOW}This script will:${NC}"
    echo "1. Check system requirements (Ubuntu 24.04+, FileMaker Server, etc.)"
    echo "2. Let you choose your DNS provider"
    echo "3. Test your DNS provider credentials"
    echo "4. Install all required packages"
    echo "5. Download and install the certificate manager script"
    echo
    read -p "Press Enter to continue or Ctrl+C to exit..."
    echo
}

# Check if running as root
check_root() {
    log_step "Checking if running as root..."
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        log_error "Please run: sudo $0"
        exit 1
    fi
    log_success "Running as root"
}

# Check Ubuntu version
check_ubuntu() {
    log_step "Checking Ubuntu version..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_error "This script only supports Ubuntu"
            log_error "Detected: $PRETTY_NAME"
            exit 1
        fi
        
        # Check if version is 24.04 or above
        if [[ "$VERSION_ID" < "24.04" ]]; then
            log_error "This script requires Ubuntu 24.04 LTS or above"
            log_error "Detected: $PRETTY_NAME"
            exit 1
        fi
    else
        log_error "Cannot detect operating system"
        exit 1
    fi
    
    log_success "Detected OS: $PRETTY_NAME"
}

# Check FileMaker Server installation
check_filemaker_server() {
    log_step "Checking FileMaker Server installation..."
    if ! command -v fmsadmin &> /dev/null; then
        log_error "FileMaker Server is not installed or fmsadmin is not available"
        log_error "Please install FileMaker Server first"
        exit 1
    fi
    log_success "FileMaker Server is installed"
}

# Check fmshelper service
check_fmshelper_service() {
    log_step "Checking fmshelper service..."
    if ! systemctl is-active --quiet fmshelper; then
        log_error "fmshelper service is not running"
        log_error "Please start FileMaker Server first"
        exit 1
    fi
    log_success "fmshelper service is running"
}

# Check if FileMaker Server scripts directory exists

check_fms_scripts_directory() {
    log_step "Checking FileMaker Server scripts directory..."
    local script_dir="/opt/FileMaker/FileMaker Server/Data/Scripts"
    if [[ ! -d "$script_dir" ]]; then
        log_error "FileMaker Server scripts directory does not exist: $script_dir"
        log_error "Please ensure FileMaker Server is properly installed"
        exit 1
    fi
    log_success "FileMaker Server scripts directory found: $script_dir"
}

# DNS provider selection menu
select_dns_provider() {
    log_step "Selecting DNS provider..."
    echo
    echo "Which DNS provider do you want to use for Let's Encrypt DNS challenges?"
    echo
    echo "1) DigitalOcean"
    echo "2) AWS Route53"
    echo "3) Linode"
    echo
    while true; do
        read -p "Enter your choice (1-3): " choice
        case $choice in
            1)
                DNS_PROVIDER="digitalocean"
                log_success "Selected DigitalOcean DNS"
                break
                ;;
            2)
                DNS_PROVIDER="route53"
                log_success "Selected AWS Route53 DNS"
                break
                ;;
            3)
                DNS_PROVIDER="linode"
                log_success "Selected Linode DNS"
                break
                ;;
            *)
                log_error "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
}

# Get domain name
get_domain_name() {
    log_step "Getting domain name..."
    echo
    echo "Enter the fully qualified domain name for your SSL certificate."
    echo "This domain must be managed by your selected DNS provider ($DNS_PROVIDER)."
    echo
    while true; do
        read -p "Fully qualified domain name (e.g. filemaker.example.com): " DOMAIN_NAME
        if [[ -n "$DOMAIN_NAME" ]] && [[ "$DOMAIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
            log_success "Domain name: $DOMAIN_NAME"
            break
        else
            log_error "Invalid domain name. Please enter a valid domain (e.g. filemaker.example.com)"
        fi
    done
}

# Get DNS provider credentials
get_dns_credentials() {
    log_step "Getting DNS provider credentials..."
    echo
    echo "You need to provide credentials for $DNS_PROVIDER."
    echo "Make sure you have configured the appropriate access tokens or IAM policies. See README.md for more information."
    echo
    
    case "$DNS_PROVIDER" in
        "digitalocean")
            echo "For DigitalOcean, you need an API token with DNS read/write permissions."
            echo "Create one at: https://cloud.digitalocean.com/account/api/tokens"
            echo
            while true; do
                if [[ -n "${DO_TOKEN:-}" ]]; then
                    read -p "DigitalOcean API Token [$DO_TOKEN]: " input_token
                    DO_TOKEN="${input_token:-$DO_TOKEN}"
                else
                    read -p "DigitalOcean API Token: " DO_TOKEN
                fi
                if [[ -n "$DO_TOKEN" ]]; then
                    log_success "DigitalOcean token provided"
                    break
                else
                    log_error "API token cannot be empty"
                fi
            done
            ;;
        "route53")
            echo "For AWS Route53, you need an IAM user with Route53 permissions."
            echo "Required permissions: route53:ChangeResourceRecordSets, route53:GetChange, route53:ListHostedZones"
            echo
            while true; do
                if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
                    read -p "AWS Access Key ID [$AWS_ACCESS_KEY_ID]: " input_key
                    AWS_ACCESS_KEY_ID="${input_key:-$AWS_ACCESS_KEY_ID}"
                else
                    read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
                fi
                if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
                    break
                else
                    log_error "Access Key ID cannot be empty"
                fi
            done
            while true; do
                if [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
                    read -p "AWS Secret Access Key [${AWS_SECRET_ACCESS_KEY:0:4}****]: " input_secret
                    AWS_SECRET_ACCESS_KEY="${input_secret:-$AWS_SECRET_ACCESS_KEY}"
                else
                    read -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
                fi
                if [[ -n "$AWS_SECRET_ACCESS_KEY" ]]; then
                    log_success "AWS credentials provided"
                    break
                else
                    log_error "Secret Access Key cannot be empty"
                fi
            done
            ;;
        "linode")
            echo "For Linode, you need an API token with DNS read/write permissions."
            echo "Create one at: https://cloud.linode.com/profile/tokens"
            echo
            while true; do
                if [[ -n "${LINODE_TOKEN:-}" ]]; then
                    read -p "Linode API Token [$LINODE_TOKEN]: " input_token
                    LINODE_TOKEN="${input_token:-$LINODE_TOKEN}"
                else
                    read -p "Linode API Token: " LINODE_TOKEN
                fi
                if [[ -n "$LINODE_TOKEN" ]]; then
                    log_success "Linode token provided"
                    break
                else
                    log_error "API token cannot be empty"
                fi
            done
            ;;
    esac
}

# Test DNS provider
test_dns_provider() {
    log_step "Testing $DNS_PROVIDER DNS access..."
    echo
    echo "This will test your DNS credentials using certbot --dry-run:"
    echo "• Creates a test TXT record for: $DOMAIN_NAME"
    echo "• Verifies DNS challenge works with your provider"
    echo "• No certificates created, no files left behind"
    echo
    read -p "Continue with DNS test? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_warn "Skipping DNS test"
        return 0
    fi
    
    # Create temporary credentials file if needed
    local temp_creds=""
    case "$DNS_PROVIDER" in
        "digitalocean")
            temp_creds="/tmp/digitalocean-test.ini"
            cat > "$temp_creds" << EOF
dns_digitalocean_token = $DO_TOKEN
EOF
            chmod 600 "$temp_creds"
            ;;
        "linode")
            temp_creds="/tmp/linode-test.ini"
            cat > "$temp_creds" << EOF
dns_linode_key = $LINODE_TOKEN
EOF
            chmod 600 "$temp_creds"
            ;;
        "route53")
            # Route53 uses environment variables
            export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
            export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
            ;;
    esac
    
    # Build certbot command
    local certbot_cmd="certbot certonly"
    
    # Add DNS provider specific options
    case "$DNS_PROVIDER" in
        "digitalocean")
            certbot_cmd="$certbot_cmd --dns-digitalocean --dns-digitalocean-credentials $temp_creds"
            ;;
        "route53")
            certbot_cmd="$certbot_cmd --dns-route53"
            ;;
        "linode")
            certbot_cmd="$certbot_cmd --dns-linode --dns-linode-credentials $temp_creds"
            ;;
    esac
    
    # Add common options
    certbot_cmd="$certbot_cmd --agree-tos --non-interactive --no-autorenew --dry-run"
    certbot_cmd="$certbot_cmd --email test@$DOMAIN_NAME -d $DOMAIN_NAME"
    certbot_cmd="$certbot_cmd --config-dir /tmp/certbot-test --work-dir /tmp/certbot-test --logs-dir /tmp/certbot-test"
    
    # Execute test with live output
    log_info "Running certbot DNS challenge test..."
    echo
    
    # Run certbot and show output in real-time
    if eval "$certbot_cmd"; then
        echo
        log_success "$DNS_PROVIDER DNS test completed successfully"
        # Clean up
        rm -rf /tmp/certbot-test
        [[ -n "$temp_creds" ]] && rm -f "$temp_creds"
        return 0
    else
        local certbot_exit_code=$?
        echo
        log_error "$DNS_PROVIDER DNS test failed (exit code: $certbot_exit_code)"
        log_error "This could be due to:"
        log_error "  • Invalid DNS credentials"
        log_error "  • Domain not managed by $DNS_PROVIDER"
        log_error "  • Insufficient API permissions"
        log_error "  • Network connectivity issues"
        echo
        echo "What would you like to do?"
        echo "1) Try again (re-enter credentials)"
        echo "2) Continue anyway (skip DNS test)"
        echo "3) Exit installation"
        echo
        read -p "Enter your choice (1-3): " choice
        
        # Clean up
        rm -rf /tmp/certbot-test
        [[ -n "$temp_creds" ]] && rm -f "$temp_creds"
        
        case "$choice" in
            1)
                log_info "Let's try again..."
                echo
                get_dns_credentials
                test_dns_provider
                return $?
                ;;
            2)
                log_warn "Continuing despite DNS test failure..."
                return 0
                ;;
            3|*)
                log_error "Installation aborted"
                exit 1
                ;;
        esac
    fi
}

# Install packages
install_packages() {
    log_step "Installing required packages..."
    echo
    echo "Installing the following packages:"
    echo "• certbot (Let's Encrypt client)"
    echo "• DNS provider plugin for $DNS_PROVIDER"
    echo "• curl, openssl, jq (utilities)"
    echo
    read -p "Continue with package installation? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_error "Package installation cancelled"
        exit 1
    fi
    
    # Update package list
    log_info "Updating package list..."
    apt update -y
    
    # Install packages based on DNS provider
    log_info "Installing certbot, $DNS_PROVIDER plugin, and utilities..."
    case "$DNS_PROVIDER" in
        "digitalocean")
            apt install -y certbot python3-certbot-dns-digitalocean curl openssl jq
            ;;
        "route53")
            apt install -y certbot python3-certbot-dns-route53 curl openssl jq
            ;;
        "linode")
            apt install -y certbot python3-certbot-dns-linode curl openssl jq
            ;;
    esac
    
    log_success "Packages installed successfully"
}

# Download and install certificate manager script
install_certificate_manager() {
    log_step "Installing certificate manager script..."
    echo
    echo "This will download the certificate manager script from GitHub and install it to:"
    echo "/opt/FileMaker/FileMaker Server/Data/Scripts/simple-certificate-manager.sh"
    echo
    read -p "Continue with script installation? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_error "Script installation cancelled"
        exit 1
    fi
    
    # Set script directory
    local script_dir="/opt/FileMaker/FileMaker Server/Data/Scripts"
    
    # Download the script
    log_info "Downloading certificate manager script..."
    if curl -sSL "https://raw.githubusercontent.com/DanSmith888/simple-certificate-manager/main/simple-certificate-manager.sh" -o "$script_dir/simple-certificate-manager.sh"; then
        log_success "Script downloaded successfully"
    else
        log_error "Failed to download script"
        exit 1
    fi
    
    # Make script executable
    chmod +x "$script_dir/simple-certificate-manager.sh"
    
    # Set proper ownership
    chown fmserver:fmsadmin "$script_dir/simple-certificate-manager.sh"
    
    log_success "Certificate manager script installed successfully"
}

# Setup sudo permissions for fmserver user
setup_sudo_permissions() {
    log_step "Setting up sudo permissions for fmserver user..."
    echo
    echo "The certificate manager script needs to run with elevated privileges to:"
    echo "• Import certificates into FileMaker Server using fmsadmin"
    echo "• Restart the FileMaker Server service when certificates are updated"
    echo
    echo "We will create a secure sudoers file that allows the fmserver user to run"
    echo "ONLY the certificate manager script with sudo (no password required)."
    echo
    echo "==== The following will be written to /etc/sudoers.d/90-fmserver ===="
    echo "fmserver ALL=(ALL) NOPASSWD: /opt/FileMaker/FileMaker\ Server/Data/Scripts/simple-certificate-manager.sh"
    echo "====================================================================="
    echo "Permissions: 440 (read-only, only root can modify)"
    echo
    read -p "Continue with sudo setup? (y/N): " setup_sudo
    
    if [[ "$setup_sudo" != "y" && "$setup_sudo" != "Y" ]]; then
        log_warn "Sudo setup skipped. Certificate manager will not be able to import certificates or restart FileMaker Server."
        return 0
    fi
    
    local sudoers_file="/etc/sudoers.d/90-fmserver"
    
    # Create the sudoers file
    log_info "Creating sudoers file..."
    cat > "$sudoers_file" << EOF
# Allow fmserver user to run certificate manager script with sudo
fmserver ALL=(ALL) NOPASSWD: /opt/FileMaker/FileMaker\\ Server/Data/Scripts/simple-certificate-manager.sh
EOF
    
    # Set proper permissions
    chmod 440 "$sudoers_file"
    
    # Verify the file was created
    if [[ -f "$sudoers_file" ]]; then
        log_success "Sudo permissions configured"
        log_info "Created: $sudoers_file"
        log_info "Permissions: $(ls -l "$sudoers_file")"
        echo
        
        # Test sudo permissions by running script with -v as fmserver user
        log_info "Testing sudo permissions..."
        local test_result
        test_result=$(sudo -u fmserver /opt/FileMaker/FileMaker\ Server/Data/Scripts/simple-certificate-manager.sh -v 2>&1)
        local test_exit_code=$?
        
        if [[ $test_exit_code -eq 0 ]]; then
            log_success "Sudo permissions test passed"
            log_info "Script version: $(echo "$test_result" | head -n1)"
        else
            log_error "Sudo permissions test failed (exit code: $test_exit_code)"
            log_error "Output: $test_result"
            log_warn "The script may not work correctly in scheduled tasks"
        fi
    else
        log_error "Failed to create sudoers file: $sudoers_file"
        return 1
    fi
}

# Setup FileMaker Server script schedule
setup_fms_schedule() {
    log_step "Setting up FileMaker Server script schedule..."
    echo
    echo "Would you like to create an automated FileMaker Server script schedule?"
    echo
    echo "This will create a scheduled task that will:"
    echo "• Check for certificate renewal needs"
    echo "• Create/renew SSL certificates using Let's Encrypt"
    echo "• Import certificates into FileMaker Server"
    echo "• Restart FileMaker Server service when needed"
    echo
    echo "The schedule will run every Sunday at 3:00 AM by default."
    echo "You can adjust the script schedule day/time to suit your maintenance window, though it is recommended to run it at least once a week to ensure certificates are renewed before expiry."
    echo
    read -p "Create automated schedule? (y/N): " create_schedule
    
    if [[ "$create_schedule" != "y" && "$create_schedule" != "Y" ]]; then
        log_info "Skipping schedule setup. You can set this up manually later."
        return 0
    fi
    
    # Get FileMaker Server credentials
    log_step "Getting FileMaker Server credentials..."
    echo
    echo "We need FileMaker Server Admin Console credentials to create the schedule."
    echo
    while true; do
        read -p "FileMaker Admin Console username: " FMS_USERNAME
        if [[ -n "$FMS_USERNAME" ]]; then
            break
        else
            log_error "Username cannot be empty"
        fi
    done
    
    while true; do
        read -p "FileMaker Admin Console password: " FMS_PASSWORD
        if [[ -n "$FMS_PASSWORD" ]]; then
            break
        else
            log_error "Password cannot be empty"
        fi
    done
    
    # Get email for Let's Encrypt
    while true; do
        read -p "Email address for Let's Encrypt notifications: " EMAIL
        if [[ -n "$EMAIL" ]] && [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            log_error "Please enter a valid email address"
        fi
    done
    
    
    # Show the command that will be scheduled
    log_step "Certificate manager command configuration..."
    echo
    echo "The following System Script will be scheduled in FileMaker Server:"
    echo
    echo "Script Name: SSL Certificate Manager"
    echo "System Script: simple-certificate-manager.sh"
    echo
    echo "Parameters:"
    case "$DNS_PROVIDER" in
        "digitalocean")
            echo "  --hostname $DOMAIN_NAME \\"
            echo "  --email $EMAIL \\"
            echo "  --dns-provider digitalocean \\"
            echo "  --do-token $DO_TOKEN \\"
            echo "  --fms-username $FMS_USERNAME \\"
            echo "  --fms-password $FMS_PASSWORD \\"
            echo "  --import-cert --restart-fms"
            ;;
        "route53")
            echo "  --hostname $DOMAIN_NAME \\"
            echo "  --email $EMAIL \\"
            echo "  --dns-provider route53 \\"
            echo "  --aws-access-key-id $AWS_ACCESS_KEY_ID \\"
            echo "  --aws-secret-key $AWS_SECRET_ACCESS_KEY \\"
            echo "  --fms-username $FMS_USERNAME \\"
            echo "  --fms-password $FMS_PASSWORD \\"
            echo "  --import-cert --restart-fms"
            ;;
        "linode")
            echo "  --hostname $DOMAIN_NAME \\"
            echo "  --email $EMAIL \\"
            echo "  --dns-provider linode \\"
            echo "  --linode-token $LINODE_TOKEN \\"
            echo "  --fms-username $FMS_USERNAME \\"
            echo "  --fms-password $FMS_PASSWORD \\"
            echo "  --import-cert --restart-fms"
            ;;
    esac
    echo
    echo -e "${YELLOW}Note: Currently configured in staging mode. Test the schedule manually first.${NC}"
    echo -e "${YELLOW}When ready for production, add --live flag and update the schedule.${NC}"
    echo
    read -p "Continue with schedule creation? (y/N): " continue_schedule
    
    if [[ "$continue_schedule" != "y" && "$continue_schedule" != "Y" ]]; then
        log_info "Schedule creation cancelled. You can set this up manually later."
        return 0
    fi
    
    # Authenticate with FileMaker Admin API
    log_info "Authenticating with FileMaker Server Admin API..."
    echo
    
    local auth_url="https://localhost/fmi/admin/api/v2/user/auth"
    local auth_response
    
    # Make authentication request
    log_info "Making authentication request to: $auth_url"
    log_info "Using credentials: $FMS_USERNAME"
    auth_response=$(curl -s -k --connect-timeout 10 --max-time 30 -X POST \
        -H "Content-Type: application/json" \
        -u "$FMS_USERNAME:$FMS_PASSWORD" \
        -d '{}' \
        "$auth_url" 2>&1)
    
    local curl_exit_code=$?
    
    # Check curl exit code first
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to connect to FileMaker Server Admin API (curl exit code: $curl_exit_code)"
        log_error "Response: $auth_response"
        log_error "Please check if FileMaker Server is running and accessible"
        return 1
    fi
    
    # Check if authentication was successful
    if echo "$auth_response" | jq -e '.response.token' >/dev/null 2>&1; then
        local fms_token=$(echo "$auth_response" | jq -r '.response.token')
        log_success "Successfully authenticated with FileMaker Server Admin API"
        log_info "Admin API Token: ${fms_token:0:20}..."
        echo
    else
        log_error "Failed to authenticate with FileMaker Server Admin API"
        log_error "Response: $auth_response"
        log_error "Please check your FileMaker Server credentials and try again"
        return 1
    fi
    
    # Brief pause before schedule creation
    sleep 2
    
    # Create FileMaker Server schedule via API
    log_info "Creating FileMaker Server schedule..."
    echo
    
    # Build parameters string based on DNS provider
    local script_params=""
    case "$DNS_PROVIDER" in
        "digitalocean")
            script_params="--hostname $DOMAIN_NAME --email $EMAIL --dns-provider digitalocean --do-token $DO_TOKEN --fms-username $FMS_USERNAME --fms-password $FMS_PASSWORD --import-cert --restart-fms"
            ;;
        "route53")
            script_params="--hostname $DOMAIN_NAME --email $EMAIL --dns-provider route53 --aws-access-key-id $AWS_ACCESS_KEY_ID --aws-secret-key $AWS_SECRET_ACCESS_KEY --fms-username $FMS_USERNAME --fms-password $FMS_PASSWORD --import-cert --restart-fms"
            ;;
        "linode")
            script_params="--hostname $DOMAIN_NAME --email $EMAIL --dns-provider linode --linode-token $LINODE_TOKEN --fms-username $FMS_USERNAME --fms-password $FMS_PASSWORD --import-cert --restart-fms"
            ;;
    esac
    
    # Create schedule JSON payload
    local schedule_payload=$(cat << EOF
{
  "name": "Simple Certificate Manager",
  "enabled": true,
  "systemScriptType": {
    "osScript": "filelinux:/opt/FileMaker/FileMaker Server/Data/Scripts/simple-certificate-manager.sh",
    "osScriptParam": "$script_params",
    "autoAbort": true,
    "timeout": 2
  },
  "weeklyType": {
    "daysOfTheWeek": ["SUN"],
    "startTimeStamp": "2000-01-01T03:00:00"
  }
}
EOF
)
    
    # Create the schedule
    local schedule_url="https://localhost/fmi/admin/api/v2/schedules/systemscript"
    local schedule_response
    
    log_info "Creating SSL Certificate Manager schedule..."
    log_info "Making schedule creation request to: $schedule_url"
    schedule_response=$(curl -s -k --connect-timeout 10 --max-time 30 -X POST \
        -H "Authorization: Bearer $fms_token" \
        -H "Content-Type: application/json" \
        -d "$schedule_payload" \
        "$schedule_url" 2>&1)
    
    local curl_exit_code=$?
    
    # Check curl exit code first
    if [[ $curl_exit_code -ne 0 ]]; then
        log_error "Failed to connect to FileMaker Server Admin API for schedule creation (curl exit code: $curl_exit_code)"
        log_error "Response: $schedule_response"
        log_error "Please check if FileMaker Server is running and accessible"
        # Still logout even if schedule creation failed
        log_info "Logging out of FileMaker Server Admin API..."
        curl -s -X DELETE \
            -H "Authorization: Bearer $fms_token" \
            "https://localhost/fmi/admin/api/v2/user/auth/$fms_token" >/dev/null 2>&1
        return 1
    fi
    
    # Check if schedule creation was successful (200 response is success)
    if echo "$schedule_response" | jq -e '.response.id' >/dev/null 2>&1; then
        local schedule_id=$(echo "$schedule_response" | jq -r '.response.id')
        log_success "SSL Certificate Manager schedule created successfully"
        echo
        echo "=========================================="
        echo "Schedule Details:"
        echo "=========================================="
        echo "Schedule ID: $schedule_id"
        echo "Schedule Name: Simple Certificate Manager"
        echo "Frequency: Every Sunday at 3:00 AM"
        echo "System Script: simple-certificate-manager.sh"
        echo "Status: Enabled"
        echo
        echo "Parameters:"
        echo "  --hostname $DOMAIN_NAME"
        echo "  --email $EMAIL"
        echo "  --dns-provider $DNS_PROVIDER"
        case "$DNS_PROVIDER" in
            "digitalocean")
                echo "  --do-token $DO_TOKEN"
                ;;
            "route53")
                echo "  --aws-access-key-id $AWS_ACCESS_KEY_ID"
                echo "  --aws-secret-key $AWS_SECRET_ACCESS_KEY"
                ;;
            "linode")
                echo "  --linode-token $LINODE_TOKEN"
                ;;
        esac
        echo "  --fms-username $FMS_USERNAME"
        echo "  --fms-password $FMS_PASSWORD"
        echo "  --import-cert"
        echo "  --restart-fms"
        echo
        echo "Mode: STAGING (test certificates)"
        echo "=========================================="
        echo
    elif echo "$schedule_response" | jq -e '.messages' >/dev/null 2>&1; then
        # Check if it's a success message (200 response with messages)
        log_success "SSL Certificate Manager schedule created successfully"
        echo
        echo "=========================================="
        echo "Schedule Details:"
        echo "=========================================="
        echo "Schedule Name: Simple Certificate Manager"
        echo "Frequency: Every Sunday at 3:00 AM"
        echo "System Script: simple-certificate-manager.sh"
        echo "Status: Enabled"
        echo "Mode: STAGING (test certificates)"
        echo "=========================================="
        echo
    else
        log_error "Failed to create FileMaker Server schedule"
        log_error "Response: $schedule_response"
        log_warn "You can manually create the schedule in FileMaker Server Admin Console"
        # Still logout even if schedule creation failed
        log_info "Logging out of FileMaker Server Admin API..."
        curl -s -k -X DELETE \
            -H "Authorization: Bearer $fms_token" \
            "https://localhost/fmi/admin/api/v2/user/auth/$fms_token" >/dev/null 2>&1
        return 1
    fi
    
    # Brief pause before logout
    sleep 2
    
    # Logout from FileMaker Server Admin API
    log_info "Logging out of FileMaker Server Admin API..."
    local logout_url="https://localhost/fmi/admin/api/v2/user/auth/$fms_token"
    local logout_response
    
    log_info "Making logout request to: $logout_url"
    logout_response=$(curl -s -k --connect-timeout 10 --max-time 30 -X DELETE \
        -H "Authorization: Bearer $fms_token" \
        "$logout_url" 2>&1)
    
    local curl_exit_code=$?
    
    # Check curl exit code first
    if [[ $curl_exit_code -ne 0 ]]; then
        log_warn "Failed to logout from FileMaker Server Admin API (curl exit code: $curl_exit_code)"
        log_warn "Response: $logout_response"
        log_warn "Session may still be active, but continuing..."
    else
        # Check if logout was successful
        if echo "$logout_response" | jq -e '.messages[0].code' >/dev/null 2>&1; then
            log_success "Successfully logged out of FileMaker Server Admin API"
        else
            log_warn "Logout response: $logout_response"
        fi
    fi
    
    log_success "Schedule setup completed"
}

# Show completion message
show_completion() {
    echo
    log_success "Installation completed successfully!"
    echo
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo -e "${BOLD}${CYAN}  Next Steps - Testing & Production  ${NC}"
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo
    echo -e "${BOLD}1. Test the Schedule Manually${NC}"
    echo
    echo "   Go to FileMaker Server Admin Console → Configuration → Schedules"
    echo "   Find: 'Simple Certificate Manager'"
    echo "   Click: 'Run Schedule Now'"
    echo
    echo "   This will create a STAGING certificate (not trusted by browsers)."
    echo "   FileMaker Server will restart if the certificate is successfully imported."
    echo
    echo -e "${BOLD}2. Switch to Production Certificates${NC}"
    echo
    echo "   Once testing is successful, update the schedule to use production certificates:"
    echo "   • Edit the schedule in FileMaker Server Admin Console"
    echo "   • Add '--live' flag to the parameters"
    echo "   • Run the schedule again"
    echo
    echo -e "${YELLOW}   ⚠️  IMPORTANT - Let's Encrypt Rate Limits:${NC}"
    echo "   • 5 duplicate certificates per week"
    echo "   • 50 certificates per domain per week"
    echo "   • Test with staging first to avoid hitting limits!"
    echo "   • More info: https://letsencrypt.org/docs/rate-limits/"
    echo
    echo -e "${BOLD}3. Optional: Remove Auto-Restart${NC}"
    echo
    echo "   If you prefer to restart FileMaker Server manually:"
    echo "   • Edit the schedule in FileMaker Server Admin Console"
    echo "   • Remove '--restart-fms' flag from the parameters"
    echo "   • You'll need to manually restart after certificate renewal"
    echo
    echo -e "${BOLD}4. Monitor Logs${NC}"
    echo
    echo "   Certificate Manager Logs:"
    echo "   • /opt/FileMaker/FileMaker Server/CStore/Certbot/logs/cert-manager.log"
    echo "   • /opt/FileMaker/FileMaker Server/CStore/Certbot/logs/fms-import.log"
    echo
    echo "   Certbot Logs:"
    echo "   • /opt/FileMaker/FileMaker Server/CStore/Certbot/logs/letsencrypt.log"
    echo
    echo -e "${BOLD}5. Schedule Details${NC}"
    echo
    echo "   Schedule Name: Simple Certificate Manager"
    echo "   Frequency: Every Sunday at 3:00 AM"
    echo "   Action: Check for renewal, import cert, restart if needed"
    echo
    echo "   You can adjust the schedule day/time in FileMaker Server Admin Console"
    echo "   to match your preferred maintenance window."
    echo
    echo -e "${BOLD}6. Smart State Management${NC}"
    echo
    echo "   The certificate manager uses semi intelligent state tracking:"
    echo
    echo "   • First Run: Requests new certificate"
    echo "   • Subsequent Runs: Only renews if certificate expires within 30 days"
    echo "   • State File: /opt/FileMaker/FileMaker Server/CStore/Certbot/simple-certificate-manager-state.json"
    echo "   • Environment Changes: Switching staging/live triggers new certificate request"
    echo "   • Hostname Changes: Changing domain triggers new certificate request"
    echo
    echo -e "${BOLD}7. Debugging${NC}"
    echo
    echo "   If you encounter issues, add the '--debug' flag to see detailed output:"
    echo "   • Edit the schedule in FileMaker Server Admin Console"
    echo "   • Add '--debug' to the parameters"
    echo "   • Check logs for detailed execution information"
    echo
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo
    echo "For detailed instructions, see: $SCRIPT_GITHUB"
    echo
    echo "Questions or issues? Open an issue on GitHub!"
    echo
    echo "Made in Australia by Daniel Smith"
    echo "https://github.com/DanSmith888"
    echo
    log_success "Happy certificate managing!"
}

# Main execution
main() {
    show_welcome
    check_root
    check_ubuntu
    check_filemaker_server
    check_fmshelper_service
    check_fms_scripts_directory
    select_dns_provider
    get_domain_name
    get_dns_credentials
    install_packages
    test_dns_provider
    install_certificate_manager
    setup_sudo_permissions
    setup_fms_schedule
    show_completion
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
