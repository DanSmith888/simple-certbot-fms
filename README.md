# Simple Certificate Manager for FileMaker Server

**Simple Certificate Manager for FileMaker Server** lets you install and automate Let's Encrypt SSL certificates with a single command — using secure DNS validation and built-in FileMaker Server scheduling.

## Quick Install
```bash
curl -fsSL https://raw.githubusercontent.com/DanSmith888/simple-certificate-manager/main/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh && rm /tmp/install.sh
```

## What It Does

A single-script solution for automating SSL certificates with Let’s Encrypt. No manual setup, no exposed web ports, no pain. Run the install, answer a few questions, and the script will:

1. Verify your DNS API credentials work
2. Obtain a valid Let’s Encrypt certificate  
3. Create a **FileMaker Server schedule** to handle automatic renewals in the future 

### Why it exists
FileMaker’s built-in LE certificate process relies on HTTP validation, manual configuration and multiple scripts.  
This script replaces all of that with one automated workflow using DNS validation.

### Key features
- **One-line install** – interactive setup handles everything  
- **Automatic renewals** – managed directly by FileMaker Server’s scheduler  
- **DNS challenge only** – no need to expose ports 80/443  
- **Multi-provider support** – works with DigitalOcean, AWS Route53, and Linode  
- **Container-friendly** – runs inside Docker or LXC without `snap` dependencies  
- **Smart state management** – remembers hostname/environment and certificate fingerprint; supports hostname changes and forced renewals; automatically chooses the right action so you dont need to use certbot directly. 

Inspired by [LE-dns-challenge-fms](https://github.com/markosburg/LE-dns-challenge-fms), but rewritten as a single, intelligent script that handles the entire lifecycle — install, verify, renew.


## How It Works

### Smart Certificate Management

The script provides a single command interface for all certificate operations that can be run manually or as a FileMaker system script schuedle.

```bash
./simple-certificate-manager.sh --hostname example.com --email admin@example.com --dns-provider digitalocean --do-token token --fms-username admin --fms-password admin --live --import-cert --restart-fms
```

This same command works for:
- **First-time certificate requests**
- **Certificate renewals** 
- **Domain changes**
- **Environment switches (staging→live)**

**The script automatically determines what to do** based on the current state and handles certificate imports into FileMaker Server, forced renewals, and service restarts based on the current state and the user's specified actions, No need for separate commands and scripts for different operations.

**Why This Is Good:**
- **Low complexity** - Users don't need to remember different commands for different scenarios
- **Consistent interface** - Same parameters work whether requesting, renewing, or changing domains
- **Error-proof** - Can't accidentally run the wrong command for the wrong situation
- **FileMaker-friendly** - Perfect for scheduled tasks where you want one reliable command
- **Maintenance-free** - Once configured, the schedule just works regardless of certificate state

**Decision Logic:**
1. **Check State**: Read previous certificate status from JSON state file
2. **Check Expiry**: Calculate days until current certificate expires
3. **Smart Decisions**:
   - If certificate expires in >30 days: Skip renewal (still valid)
   - If certificate expires in ≤30 days: Run certbot to renew
   - If hostname changed - request new certificate for new domain now
   - If environment changed (staging↔live) - request new certificate now
   - If `--force-renew` is set request new certificate regardless of expiry
   

**Timeline Example:**
- **Day 1**: Certificate issued (expires in 90 days) → **No action** (just save state)
- **Day 7**: Script runs via FileMaker schedule → **Check expiry: 83 days left** → **No action**
- **Day 14**: Script runs again → **Check expiry: 76 days left** → **No action**
- **Day 60**: Script runs → **Check expiry: 29 days left** → **Run certbot** → **Issue new certificate**
- **Day 67**: Script runs → **Check expiry: 83 days left** → **No action** (new cert installed)

### FileMaker Schedule Integration

**No External Schedulers**: Unlike traditional certbot setups, this script:
- Doesn't install systemd timers or cron jobs
- All scheduling handled through FileMaker Server Admin Console
- Runs as `fmserver` user with secure sudo permissions
- Single weekly schedule prevents certificate expiration
- **Everything stored in schedule**: All parameters, credentials, and settings are saved directly in the FileMaker schedule - easily backed up and restored with FileMaker Server exports


### Staging vs Live Certificates

**Staging Environment (Default):**
- Uses Let's Encrypt staging servers: `https://acme-staging-v02.api.letsencrypt.org`
- Issues test certificates that browsers don't trust
- **No rate limits** - perfect for testing and development
- **Safe to use** - won't affect your production certificate quota

**Live Environment:**
- Uses Let's Encrypt production servers: `https://acme-v02.api.letsencrypt.org`
- Issues real certificates trusted by all browsers
- **Rate limited** - 5 duplicate certs per week, 50 per domain per week
- **Production ready** - use only when everything is tested

**How to Switch:**
1. **Test with staging** (default): Run schedule as-is
2. **Switch to live**: Edit FileMaker schedule, add `--live` flag to parameters
3. **Script detects change**: Automatically requests new certificate from live servers
4. **State updates**: Remembers the switch for future runs

### Debugging & Logging

**Comprehensive Logging** to `/opt/FileMaker/FileMaker Server/CStore/Certbot/logs/`:
- `cert-manager.log` - Main script execution and decisions
- `fms-import.log` - FileMaker Server certificate import operations
- `letsencrypt.log` - Certbot DNS challenge and certificate operations

**State File** at `/opt/FileMaker/FileMaker Server/CStore/Certbot/simple-certificate-manager-state.json`:
- Tracks certificate status, hostname, and environment

### Script Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--hostname` | Yes | Domain name for the certificate |
| `--email` | Yes | Email for Let's Encrypt notifications |
| `--dns-provider` | Yes | DNS provider: `digitalocean`, `route53`, or `linode` |
| `--do-token` | Yes* | DigitalOcean API token (required for DigitalOcean DNS) |
| `--aws-access-key-id` | Yes* | AWS Access Key ID (required for Route53 DNS) |
| `--aws-secret-key` | Yes* | AWS Secret Access Key (required for Route53 DNS) |
| `--linode-token` | Yes* | Linode API token (required for Linode DNS) |
| `--live` | No | Use live Let's Encrypt (default: staging) |
| `--import-cert` | No | Import certificate to FileMaker Server using fmsadmin (default: false) |
| `--restart-fms` | No | Restart FileMaker Server after import (only when --import-cert is set) |
| `--force-renew` | No | Bypasses state checking for immediate certificate issuance |
| `--fms-username` | No* | FileMaker Admin Console username (required for certificate import) |
| `--fms-password` | No* | FileMaker Admin Console password (required for certificate import) |
| `--cleanup` | No | Remove all files and logs for a fresh start (for development/testing only) |
| `--debug` | No | Enable debug logging |
| `--version` | No | Show script version and exit |

*Required based on DNS provider selection



## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/DanSmith888/simple-certificate-manager/main/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh && rm /tmp/install.sh
```

This interactive installer will:

- **DNS Credentials**: Configure API tokens and access keys for your DNS provider
- **Package Installation**: Install certbot, DNS plugins, and required utilities
- **DNS Testing**: Test DNS challenge functionality with your provider
- **Script Installation**: Download and configure the certificate manager
- **Sudo Setup**: Configure secure permissions for the fmserver user to run the script
- **Schedule Creation**: Create automated FileMaker Server schedules
- **Completion Guide**: Provide next steps and usage instructions

### DNS Providers

Choose one:
- **DigitalOcean** - API token with DNS permissions
- **AWS Route53** - IAM user with Route53 permissions
- **Linode** - API token with DNS permissions

## Requirements

- Ubuntu 24.04 LTS or above 
- FileMaker Server 22 or above
- Supported DNS provider account and API access

> **Note:** This probably works on older Ubuntu and FileMaker Server versions but is untested. You may need to modify the scripts to bypass version checks if using older versions. macOS will not run these scripts.


## Manual Usage

If you prefer manual setup:

```bash
# 1. Install dependencies
sudo apt install -y certbot python3-certbot-dns-digitalocean python3-certbot-dns-route53 python3-certbot-dns-linode curl jq openssl

# 2. Copy script to FileMaker Server
sudo cp simple-certificate-manager.sh /opt/FileMaker/FileMaker\ Server/Data/Scripts/
sudo chmod +x /opt/FileMaker/FileMaker\ Server/Data/Scripts/simple-certificate-manager.sh

# 3. Configure sudo for fmserver user
echo "fmserver ALL=(ALL) NOPASSWD: /opt/FileMaker/FileMaker\ Server/Data/Scripts/simple-certificate-manager.sh" | sudo tee /etc/sudoers.d/90-fmserver
sudo chmod 440 /etc/sudoers.d/90-fmserver

# 4. Run the script manually or from a FileMaker schedule
sudo ./simple-certificate-manager.sh --hostname yourdomain.com --email admin@yourdomain.com --dns-provider digitalocean --do-token your_token --fms-username admin --fms-password password --live --import-cert --restart-fms
```



For issues and feature requests, please [create an issue](https://github.com/DanSmith888/simple-certificate-manager/issues) on GitHub.
