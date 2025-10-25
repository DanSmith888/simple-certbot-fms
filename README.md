# Let's Encrypt DNS Challenge for FileMaker Server

> **System Requirements:**  
> This script is **only supported on Ubuntu 24.04 LTS and above**.  
> No macOS or other Linux distributions are supported.

**Single Script Solution** for automated SSL certificate management with FileMaker Server using Let's Encrypt DNS challenges and DigitalOcean DNS support.

## Key Features

- **Single Script**: One `fms-cert-manager.sh` script handles everything
- **Drop-in Solution**: Perfect for FileMaker Server scheduled scripts
- **Parameter-Driven**: All settings passed as command-line parameters
- **No Configuration Files**: No need to manage separate config files
- **FileMaker Server Integration**: Designed specifically for FileMaker Server scheduling
- **No Auto-Renewal Conflicts**: Always uses `--no-auto-renew` to prevent certbot's built-in renewal from interfering with FileMaker Server scheduling
- **Container Friendly**: Works in LXC, Docker, and isolated environments where snap install may not be supported.

## Quick Start

### 1. Copy Script to FileMaker Server
```bash
# Copy script to FileMaker Server scripts folder
sudo cp fms-cert-manager.sh /opt/FileMaker/FileMaker\ Server/Data/Scripts/
sudo chmod +x /opt/FileMaker/FileMaker\ Server/Data/Scripts/fms-cert-manager.sh
sudo chown fmserver:fmsadmin /opt/FileMaker/FileMaker\ Server/Data/Scripts/fms-cert-manager.sh
```

### 2. Install Dependencies
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

### 3. Setup DigitalOcean
1. Create API token with **DNS: Read and Write** permissions only
2. Add your domain to DigitalOcean DNS
3. Update your domain's nameservers to DigitalOcean

### 4. Schedule in FileMaker Server
1. **Admin Console** → Configuration → Schedules → Create Schedules → New System Script
2. **Script Path**: `fms-cert-manager.sh`
3. **Parameters**: `--hostname yourdomain.com --email admin@yourdomain.com --do-token your_token --fms-username admin --fms-password password --live --import-cert --restart-fms`
4. **User**: `root` or left blank for `fmserver` (requires sudo setup above)
5. **Schedule**: Weekly execution


## Script Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--hostname` | Yes | Domain name for the certificate |
| `--email` | Yes | Email for Let's Encrypt notifications |
| `--do-token` | Yes | DigitalOcean API token |
| `--fms-username` | Yes | FileMaker Admin Console username |
| `--fms-password` | Yes | FileMaker Admin Console password |
| `--live` | No | Use live Let's Encrypt (default: sandbox/staging) |
| `--import-cert` | No | Import certificate to FileMaker Server (default: false) |
| `--restart-fms` | No | Restart FileMaker Server after import (default: false) |
| `--force-renew` | No | Force renewal even if not needed |
| `--debug` | No | Enable debug logging |

## Manual Examples

```bash
# First run - requests new certificate and creates a state file (staging by default)
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --do-token dop_v1_xxx --fms-username admin --fms-password password

# Production certificate with import and restart
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --do-token dop_v1_xxx --fms-username admin --fms-password password --live --import-cert --restart-fms

# Subsequent runs - automatically renews if needed
sudo ./fms-cert-manager.sh --hostname example.com --email admin@example.com --do-token dop_v1_xxx --fms-username admin --fms-password password --live --import-cert --restart-fms

# Debug mode
sudo ./fms-cert-manager.sh --debug --hostname example.com --email admin@example.com --do-token dop_v1_xxx --fms-username admin --fms-password password --live --import-cert --restart-fms
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


## Support

For issues and feature requests, please create an issue in this repository.