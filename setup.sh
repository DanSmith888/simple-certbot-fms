#!/bin/bash

# FileMaker Server Certificate Manager Setup Script
# Installs required packages for Let's Encrypt DNS challenge with DigitalOcean

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Check if running on Ubuntu 24.04 LTS or above
check_ubuntu() {
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
    
    log_info "Detected OS: $PRETTY_NAME"
}

# Install packages for Ubuntu 24.04 LTS and above
install_packages() {
    log_info "Installing packages for Ubuntu 24.04 LTS and above..."
    
    # Update package list
    log_info "Updating package list..."
    apt update -y
    
    # Install required packages
    log_info "Installing certbot, DigitalOcean plugin, Route53 plugin, and Linode plugin..."
    apt install -y certbot python3-certbot-dns-digitalocean python3-certbot-dns-route53 python3-certbot-dns-linode curl openssl jq
    
    log_success "Packages installed successfully"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Check certbot
    if command -v certbot &> /dev/null; then
        local certbot_version=$(certbot --version 2>&1 | head -n1)
        log_success "Certbot installed: $certbot_version"
    else
        log_error "Certbot installation failed"
        exit 1
    fi
    
    # Check DigitalOcean plugin
    if python3 -c "import certbot_dns_digitalocean" 2>/dev/null; then
        log_success "DigitalOcean DNS plugin installed"
    else
        log_error "DigitalOcean DNS plugin installation failed"
        exit 1
    fi
    
    # Check Route53 plugin
    if python3 -c "import certbot_dns_route53" 2>/dev/null; then
        log_success "Route53 DNS plugin installed"
    else
        log_error "Route53 DNS plugin installation failed"
        exit 1
    fi
    
    # Check Linode plugin
    if python3 -c "import certbot_dns_linode" 2>/dev/null; then
        log_success "Linode DNS plugin installed"
    else
        log_error "Linode DNS plugin installation failed"
        exit 1
    fi
    
    # Check other dependencies
    for cmd in curl openssl jq; do
        if command -v "$cmd" &> /dev/null; then
            log_success "$cmd is available"
        else
            log_error "$cmd is not available"
            exit 1
        fi
    done
}



# Display next steps
show_next_steps() {
    log_success "Setup completed successfully!"
    echo
    log_info "Next steps:"
    echo "1. Configure your domain in DigitalOcean DNS"
    echo "2. Create a DigitalOcean API token with DNS read/write permissions"
    echo "3. Test the certificate manager:"
    echo "   sudo ./fms-cert-manager.sh --hostname yourdomain.com --email admin@yourdomain.com --do-token your_token --sandbox"
    echo "4. Set up automated renewal in FileMaker Server Admin Console"
    echo
    log_info "For detailed instructions, see the README.md file"
}

# Main execution
main() {
    log_info "FileMaker Server Certificate Manager Setup"
    log_info "=============================================="
    echo
    
    check_root
    check_ubuntu
    install_packages
    verify_installation
    show_next_steps
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
