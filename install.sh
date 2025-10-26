#!/bin/bash

# FileMaker Server Certificate Manager Installer
# Installs the certificate manager script and dependencies for Let's Encrypt DNS challenge
# Supports DigitalOcean, AWS Route53, and Linode DNS providers

set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="FileMaker Server Certificate Manager Installer"
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

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

log_prompt() {
    echo -e "${BOLD}[PROMPT]${NC} $1"
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
    echo "curl -sSL https://raw.githubusercontent.com/DanSmith888/simple-certbot-fms/main/install.sh | sudo bash"
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
    echo "/opt/FileMaker/FileMaker Server/Data/Scripts/fms-cert-manager.sh"
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
    if curl -sSL "https://raw.githubusercontent.com/DanSmith888/simple-certbot-fms/main/fms-cert-manager.sh" -o "$script_dir/fms-cert-manager.sh"; then
        log_success "Script downloaded successfully"
    else
        log_error "Failed to download script"
        exit 1
    fi
    
    # Make script executable
    chmod +x "$script_dir/fms-cert-manager.sh"
    
    # Set proper ownership
    chown fmserver:fmsadmin "$script_dir/fms-cert-manager.sh"
    
    log_success "Certificate manager script installed successfully"
}

# Show completion message
show_completion() {
    echo
    log_success "Installation completed successfully!"
    echo
    echo -e "${BOLD}Next steps:${NC}"
    echo
    echo "1. Test the certificate manager with staging certificates:"
    case "$DNS_PROVIDER" in
        "digitalocean")
            echo "   sudo /opt/FileMaker/FileMaker\\ Server/Data/Scripts/fms-cert-manager.sh \\"
            echo "     --hostname $DOMAIN_NAME \\"
            echo "     --email admin@$DOMAIN_NAME \\"
            echo "     --dns-provider digitalocean \\"
            echo "     --do-token YOUR_TOKEN \\"
            echo "     --fms-username admin \\"
            echo "     --fms-password YOUR_PASSWORD \\"
            echo "     --import-cert --restart-fms"
            ;;
        "route53")
            echo "   sudo /opt/FileMaker/FileMaker\\ Server/Data/Scripts/fms-cert-manager.sh \\"
            echo "     --hostname $DOMAIN_NAME \\"
            echo "     --email admin@$DOMAIN_NAME \\"
            echo "     --dns-provider route53 \\"
            echo "     --aws-access-key-id YOUR_ACCESS_KEY \\"
            echo "     --aws-secret-key YOUR_SECRET_KEY \\"
            echo "     --fms-username admin \\"
            echo "     --fms-password YOUR_PASSWORD \\"
            echo "     --import-cert --restart-fms"
            ;;
        "linode")
            echo "   sudo /opt/FileMaker/FileMaker\\ Server/Data/Scripts/fms-cert-manager.sh \\"
            echo "     --hostname $DOMAIN_NAME \\"
            echo "     --email admin@$DOMAIN_NAME \\"
            echo "     --dns-provider linode \\"
            echo "     --linode-token YOUR_TOKEN \\"
            echo "     --fms-username admin \\"
            echo "     --fms-password YOUR_PASSWORD \\"
            echo "     --import-cert --restart-fms"
            ;;
    esac
    echo
    echo "2. Once testing is successful, add --live flag for production certificates"
    echo
    echo "3. Set up automated renewal in FileMaker Server Admin Console"
    echo
    echo "4. For detailed instructions, see: $SCRIPT_GITHUB"
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
    show_completion
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
