# Let's Encrypt DNS Challenge for FileMaker Server

> **System Requirements:**  
> This script is **designed and tested for Ubuntu 24.04 LTS and above**.  
> Other Linux versions may work but are not tested or supported.

**Single Script Solution** for automated SSL certificate management with FileMaker Server using built-in schedules and Let's Encrypt DNS challenges with DigitalOcean DNS support.

## Why This Script Exists

### The Problem with FileMaker Server SSL
FileMaker Server's built-in SSL certificate management is **complex and error-prone**:
- Let's Encrypt support exists but **only HTTP validation** (requires server exposed to internet)
- Confusing, brittle setup with multiple scripts and configs to manage, complicated documentation and many moving parts

### The Pain Points I'm Trying To Solve
1. **Single Script**: One file handles everything - no more managing multiple scripts
2. **Parameter-Driven**: All settings as command-line arguments - no config files
3. **Smart State Management**: Automatically decides request vs renew
4. **Hostname Flexibility**: Change your hostnames without breaking state management
5. **FileMaker Integration**: Designed specifically for FMS scheduled scripts
6. **Container Friendly**: Uses `apt` instead of `snap` packages for better compatibility
   - **Why APT?**: Snap fails in LXC, Docker, and minimal containers
   - **When APT is fine**: Manual renewals, minimal containers, embedded builds
   - **APT limitations**: Not always up-to-date, but sufficient for this use case
6. **Drop-in Solution**: Copy, configure, schedule - that's it!

### The Evolution
This script evolved from the excellent [`LE-dns-challenge-fms`](https://github.com/wimdecorte/LE-dns-challenge-fms) repository by Wim Decorte, which had:
- Multiple separate scripts
- Configuration file dependencies
- snap installer that wont easliy run in containers

**This new approach** attempts to eliminate complexity with a single, semi intelligent script.

## Key Features

- **🚀 One-Line Installation**: Single curl command installs everything
- **🤖 Interactive Setup**: Guided prompts for all configuration details
- **📅 Automatic Scheduling**: Creates FileMaker Server schedules automatically
- **🔧 API Integration**: Uses FileMaker Server Admin API for seamless setup
- **🌐 Multiple DNS Providers**: Supports both DigitalOcean and AWS Route53
- **Single Script**: One `fms-cert-manager.sh` script handles everything
- **Drop-in Solution**: Perfect for FileMaker Server scheduled scripts
- **Parameter-Driven**: All settings passed as command-line parameters in the FileMaker scheule, no need to edit config files in the OS.
- **FileMaker Server Integration**: Designed specifically for FileMaker Server scheduling
- **No Auto-Renewal Certbot Conflicts**: Silently passes `--no-auto-renew` to prevent certbot's built-in renewal scheudles from interfering with FileMaker Server scheduling


## Quick Start

### 🚀 One-Line Installation

**The easiest way to get started:**

```bash
curl -fsSL https://raw.githubusercontent.com/DanSmith888/simple-certbot-fms/main/install.sh | sudo bash
```

This single command will:
- ✅ Install all required packages (certbot, DigitalOcean plugin, etc.)
- ✅ Download and configure the certificate manager script
- ✅ Prompt you for all configuration details interactively
- ✅ Create an automated schedule in FileMaker Server
- ✅ Run an initial certificate request

### 📋 Prerequisites

Before running the installer, make sure you have:

1. **Ubuntu 24.04 LTS or above** (the installer will check this)
2. **FileMaker Server 2024 or later** installed and running
3. **DNS Provider Setup** (choose one):
   - **DigitalOcean**: Account with domain configured in DNS + API token with DNS read/write permissions
   - **AWS Route53**: Account with hosted zone + IAM user with Route53 permissions
4. **FileMaker Server Admin Console** credentials

### 🔧 Manual Installation (Alternative)

If you prefer manual installation or the one-liner doesn't work:

#### 1. Copy Script to FileMaker Server
```bash
# Copy script to FileMaker Server scripts folder
sudo cp fms-cert-manager.sh /opt/FileMaker/FileMaker\ Server/Data/Scripts/
sudo chmod +x /opt/FileMaker/FileMaker\ Server/Data/Scripts/fms-cert-manager.sh
sudo chown fmserver:fmsadmin /opt/FileMaker/FileMaker\ Server/Data/Scripts/fms-cert-manager.sh
```

#### 2. Install Dependencies
```bash
sudo ./setup.sh
```

**Note**: Do this if you plan to run the schedule as the default fmserver user (left blank in FileMaker Server scheduler):

```bash
sudo visudo
```

```bash
# Add this line to /etc/sudoers (use visudo command)
fmserver ALL=(ALL) NOPASSWD: /opt/FileMaker/FileMaker\ Server/Data/Scripts/fms-cert-manager.sh
```

#### 3. Setup DNS Provider

**For DigitalOcean:**
1. Create API token with **DNS: Read and Write** permissions only
2. Add your domain to DigitalOcean DNS
3. Update your domain's nameservers to DigitalOcean

**For AWS Route53:**
1. Create a hosted zone for your domain in Route53
2. Create an IAM user with Route53 permissions
3. Generate access keys for the IAM user
4. Update your domain's nameservers to Route53

#### 4. Schedule in FileMaker Server
1. **Admin Console** → Configuration → Schedules → Create Schedules → New System Script
2. **Script Path**: `fms-cert-manager.sh`
3. **Parameters**: `--hostname yourdomain.com --email admin@yourdomain.com --dns-provider digitalocean --do-token your_token --fms-username admin --fms-password password --live --import-cert --restart-fms`
4. **User**: `root` or left blank for `fmserver` (requires sudo setup above)
5. **Schedule**: Run the script a couple times a day (e.g., every 12 hours), similar to how Certbot's systemd timer would handle renewals. This helps ensure certificates are renewed before expiry.


## Script Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--hostname` | Yes | Domain name for the certificate |
| `--email` | Yes | Email for Let's Encrypt notifications |
| `--fms-username` | Yes | FileMaker Admin Console username |
| `--fms-password` | Yes | FileMaker Admin Console password |
| `--dns-provider` | Yes | DNS provider: `digitalocean` or `route53` |
| `--do-token` | Yes* | DigitalOcean API token (required for DigitalOcean DNS) |
| `--aws-access-key-id` | Yes* | AWS Access Key ID (required for Route53 DNS) |
| `--aws-secret-key` | Yes* | AWS Secret Access Key (required for Route53 DNS) |
| `--live` | No | Use live Let's Encrypt (default: sandbox/staging) |
| `--import-cert` | No | Import certificate to FileMaker Server (default: false) |
| `--restart-fms` | No | Restart FileMaker Server after import (default: false) |
| `--force-renew` | No | Force renewal even if not needed |
| `--import-cert` | No | Import certificate to FileMaker Server |
| `--restart-fms` | No | Restart FileMaker Server after import (only runs when --import-cert is also set) |
| `--fms-username` | No* | FileMaker Admin Console username (required for certificate import) |
| `--fms-password` | No* | FileMaker Admin Console password (required for certificate import) |

| `--cleanup` | No | Remove all certbot files and logs (for development/testing only) |
| `--debug` | No | Enable debug logging |

*Required based on DNS provider selection

## Manual Examples

### DigitalOcean DNS

```bash
# First run - requests new certificate and creates a state file (staging by default)
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --dns-provider digitalocean --do-token dop_v1_xxx --fms-username admin --fms-password password

# Production certificate with import and restart
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --dns-provider digitalocean --do-token dop_v1_xxx --fms-username admin --fms-password password --live --import-cert --restart-fms

# Subsequent runs - automatically renews if needed
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --dns-provider digitalocean --do-token dop_v1_xxx --fms-username admin --fms-password password --live --import-cert --restart-fms
```

### AWS Route53 DNS

```bash
# First run - requests new certificate and creates a state file (staging by default)
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --dns-provider route53 --aws-access-key-id AKIA... --aws-secret-key secret... --fms-username admin --fms-password password

# Production certificate with import and restart
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --dns-provider route53 --aws-access-key-id AKIA... --aws-secret-key secret... --fms-username admin --fms-password password --live --import-cert --restart-fms

# Subsequent runs - automatically renews if needed
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --dns-provider route53 --aws-access-key-id AKIA... --aws-secret-key secret... --fms-username admin --fms-password password --live --import-cert --restart-fms
```

### Debug Mode

```bash
# Debug mode with DigitalOcean
sudo ./fms-cert-manager.sh --debug --hostname example.com --email admin@example.com --dns-provider digitalocean --do-token dop_v1_xxx --fms-username admin --fms-password password --live --import-cert --restart-fms

# Debug mode with Route53
sudo ./fms-cert-manager.sh --debug --hostname example.com --email admin@example.com --dns-provider route53 --aws-access-key-id AKIA... --aws-secret-key secret... --fms-username admin --fms-password password --live --import-cert --restart-fms
```

## Smart State Management

The script automatically remembers what it did previously and makes semi-intelligent decisions:

- **First Run**: Requests new certificate
- **Subsequent Runs**: Automatically renews if certificate is close to expiry (within 30 days)
- **State Tracking**: Remembers hostname, environment (sandbox/live), and certificate status
- **Environment Changes**: If you switch from sandbox to live (or vice versa), it requests a new certificate
- **Hostname Changes**: If you change the hostname, it requests a new certificate

## Why This Approach?

**Other solutions are complex:**
- **FileMaker's built-in approach**: Involves multiple config files and tricky manual procedures
- **Traditional Let's Encrypt**: Scattered configuration and maintenance across several scripts and files
- **Other DNS challenge solutions**: Hard to automate, difficult to backup or migrate, and not easily portable

**This solution** is designed for FileMaker Server and modern workflows:

- ✅ **Single File Simplicity**: Everything in `fms-cert-manager.sh`—no need to manage extra config files
- ✅ **Parameter-Driven**: All settings are passed as command-line arguments for clarity and scripting
- ✅ **Self-Contained**: No external dependencies beyond normal system packages; logic, state, and process are all included
- ✅ **Portable and Automatable**: Easily copy or deploy between servers, including via automated tools like Ansible
- ✅ **Fully Backup-Friendly**: All that's needed is the script and its state file, which are automatically included in FileMaker Server backups, so your certificate process is backed up with schedule export/import or ordinary FMS backup

## Logging

All operations are logged to:
- `/opt/FileMaker/FileMaker Server/CStore/Certbot/logs/`

## Notes & Gotchas

### Certificate Renewal Logic
The script uses **smart renewal detection** that checks the actual certificate on file:

```bash
# Script checks certificate expiry using openssl
get_cert_expiry() {
    openssl x509 -in "$cert_file" -noout -dates | grep "notAfter"
}

# Only renews if certificate expires within 30 days
if [[ $days_until_expiry -lt 30 ]]; then
    # Renew certificate
    certbot renew --cert-name $hostname
    # Note: certbot also checks expiry and will only issue new cert if >30 days
else
    # Skip renewal - certificate is still valid
    log_info "Certificate exists and is valid"
fi
```

**Timeline Example:**
- **Day 1**: Certificate issued (expires in 90 days) → **No action**
- **Day 2-59**: Script runs twice daily → **No action** (certificate valid)
- **Day 60**: Certificate expires in 29 days → **Script runs certbot** → **Certbot issues new certificate**
- **Day 61+**: New certificate issued (expires in 90 days) → **No action** (certificate valid)

### Certificate Import Behavior
**Important**: If you run the script without `--import-cert` or the import fails, the script will not run again unless you use `--force-renew`. This is because:

- The script detects an existing certificate and considers it "valid"
- It won't attempt renewal unless the certificate is close to expiry (within 30 days)
- To force a new attempt, use: `--force-renew`

### Testing Workflow
**Important**: Always test with staging first to avoid hitting Let's Encrypt rate limits:

```bash
# Clean up all files
sudo ./fms-cert-manager.sh --cleanup

# Test with staging (default - no --live flag)
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --do-token your_token --fms-username admin --fms-password password --import-cert --restart-fms

# Only after staging works perfectly, switch to production
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --do-token your_token --fms-username admin --fms-password password --live --import-cert --restart-fms
```

**Why Staging First?**
- **No rate limits**: Staging environment has no certificate limits
- **Verify workflow**: Ensure import and restart work correctly
- **Production ready**: Only use `--live` when everything is working

## Security Considerations

### Important Caveats
**This approach has the same security considerations as FileMaker Server's native SSL management:**

- **DNS Provider Credentials**: Stored unencrypted in FileMaker Server script schedules or config files
- **FileMaker Admin Credentials**: Stored unencrypted in FileMaker Server script schedules or config files
- **Not Best Practice**: Credentials are stored in plain text
- **Same as Native**: No different from FileMaker Server's built-in SSL certificate management
- **Industry Standard**: Most FileMaker Server SSL solutions work this way

## Troubleshooting

### Debug Mode
```bash
sudo ./fms-cert-manager.sh --debug --hostname example.com --email admin@example.com --do-token your_token --live
```

### Check Logs
```bash
tail -f /opt/FileMaker/FileMaker\ Server/CStore/Certbot/logs/cert-manager.log
```

## Requirements

- **OS**: Ubuntu 24.04 LTS and above
- **FileMaker Server**: 2024 or later
- **DigitalOcean**: Domain must be managed by DigitalOcean DNS


## Installer Script Details

The `install.sh` script provides a comprehensive installation experience:

### What the Installer Does

1. **System Checks**: Verifies Ubuntu 24.04+ and FileMaker Server installation
2. **Package Installation**: Installs certbot, DigitalOcean plugin, and dependencies
3. **Interactive Configuration**: Prompts for all required settings
4. **Script Setup**: Downloads and configures the certificate manager
5. **Schedule Creation**: Creates automated schedules using multiple methods:
   - Primary: FileMaker Server Admin API
   - Fallback: fmsadmin command line
   - Manual: Provides detailed instructions if automated methods fail
6. **Initial Certificate**: Runs the first certificate request
7. **Verification**: Tests connections and provides completion summary

### Installer Features

- **🔍 Smart Detection**: Automatically detects system requirements
- **🛡️ Error Handling**: Comprehensive error checking and user guidance
- **📋 Configuration Summary**: Shows all settings before proceeding
- **🔄 Multiple Fallbacks**: Tries different methods for schedule creation
- **📝 Detailed Logging**: Clear progress indicators and error messages
- **✅ Verification**: Tests all connections before completion

### Installer Requirements

- **Root Access**: Must run as root or with sudo
- **Internet Connection**: Downloads packages and script from GitHub
- **FileMaker Server**: Must be installed and accessible
- **DigitalOcean Setup**: Domain and API token ready

## Support

For issues and feature requests, please create an issue in this repository.