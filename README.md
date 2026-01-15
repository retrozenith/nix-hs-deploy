# Nix Home Server Deploy - Andromeda

A NixOS flake configuration for deploying **Andromeda**, a home media server.

## Features

- **Jellyfin** - Open source media server (port 8096)
- **Sonarr** - TV show management and automation (port 8989)
- **Radarr** - Movie management and automation (port 7878)
- **Prowlarr** - Indexer management for Sonarr/Radarr (port 9696)
- **Jellyseerr** - Media request management (port 5055)
- **Streamystats** - Jellyfin analytics and statistics (port 3000)
- **qBittorrent** - BitTorrent client with web UI (port 8080)
- **Gluetun** - VPN container for qBittorrent (NordVPN WireGuard)
- **Vaultwarden** - Self-hosted Bitwarden password manager (port 8222)
- **Caddy** - Reverse proxy with automatic HTTPS (ports 80, 443)
- **Cloudflare DDNS** - Automatic DNS updates for dynamic IP
- **Dynamic MOTD** - System info, IPs, and service links on SSH login

## Project Structure

```
nix-hs-deploy/
├── flake.nix                          # Main flake configuration
├── .github/
│   └── workflows/
│       ├── ci.yml                     # CI checks on PRs and pushes
│       ├── update.yml                 # Automated flake updates
│       └── deploy.yml                 # Manual deployment workflow
├── hosts/
│   └── andromeda/
│       ├── default.nix                # Host-specific configuration
│       └── hardware-configuration.nix # Hardware config (generate on target)
├── scripts/
│   ├── install.sh                     # First-time installation script
│   ├── deploy.sh                      # Quick deployment script
│   └── generate-secrets.sh            # Secrets generation script
└── modules/
    ├── services/
    │   ├── media/
    │   │   ├── default.nix            # Media services bundle
    │   │   ├── jellyfin.nix           # Jellyfin media server
    │   │   ├── sonarr.nix             # Sonarr TV management
    │   │   ├── radarr.nix             # Radarr movie management
    │   │   ├── prowlarr.nix           # Prowlarr indexer manager
    │   │   ├── jellyseerr.nix         # Jellyseerr request manager
    │   │   ├── qbittorrent-vpn.nix    # qBittorrent with VPN (Gluetun)
    │   │   └── streamystats.nix       # Jellyfin statistics
    │   ├── networking/
    │   │   ├── caddy.nix              # Caddy reverse proxy
    │   │   └── cloudflare-ddns.nix    # Cloudflare DDNS updater
    │   └── misc/
    │       └── vaultwarden.nix        # Vaultwarden password manager
    ├── storage/
    │   └── mergerfs.nix               # MergerFS storage pool module
    ├── motd.nix                       # Dynamic MOTD with system info
    └── tailscale.nix                  # Tailscale VPN module
```

## Prerequisites

- NixOS installed on target machine
- Flakes enabled
- SSH access to the target machine

## Quick Start

For first-time installation, use the automated install script:

```bash
# Clone the repository
git clone https://github.com/yourusername/nix-hs-deploy.git
cd nix-hs-deploy

# Run the installation script
./scripts/install.sh --server-ip 192.168.0.26
```

The install script will guide you through:
1. **Prerequisites check** - Verifies required tools are installed
2. **Server connection** - Tests SSH connectivity
3. **Host key setup** - Retrieves and configures the server's SSH host key
4. **Disk formatting** - Interactive disk setup for MergerFS storage pool
5. **Hardware configuration** - Generates hardware-configuration.nix from the server
6. **Secrets generation** - Creates encrypted secrets from .env.secrets
7. **First deployment** - Builds and deploys the NixOS configuration

### Install Script Options

```bash
./scripts/install.sh [options]

Options:
  --server-ip <ip>       Server IP address (default: 192.168.0.26)
  --server-user <user>   SSH user on server (default: root)
  --skip-disks           Skip disk formatting step
  --skip-secrets         Skip secrets generation step
  --skip-deploy          Skip deployment step (prepare only)
  --help                 Show help message
```

### Subsequent Deployments

After initial setup, use the quick deploy script:

```bash
# Standard deployment
./scripts/deploy.sh

# Deploy via Tailscale
./scripts/deploy.sh --tailscale

# Test configuration first (doesn't persist after reboot)
./scripts/deploy.sh --test

# Build only (check for errors without deploying)
./scripts/deploy.sh --build-only

# Rollback to previous configuration
./scripts/deploy.sh --rollback
```

## Setup

### 1. Generate Hardware Configuration

On the target machine (Andromeda), generate the hardware configuration:

```bash
nixos-generate-config --show-hardware-config > /tmp/hardware-configuration.nix
```

Copy this file to `hosts/andromeda/hardware-configuration.nix` replacing the template.

### 2. Configure Network Settings

Edit `hosts/andromeda/default.nix` and adjust:

- Static IP address (default: `192.168.0.26`)
- Gateway (default: `192.168.0.1`)
- Network interface name (default: `eth0`)
- Timezone (default: `Europe/Bucharest`)

### 3. Add SSH Keys

Add your SSH public key to `hosts/andromeda/default.nix`:

```nix
users.users.admin = {
  openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAA... your-key-here"
  ];
};
```

### 4. Configure Media Directories

The default directories are:

- `/srv/media` - Media library (movies, TV, music)
- `/srv/downloads` - Download directory for qBittorrent

Adjust these in the host configuration if needed.

## Deployment

### Local Build and Switch

On the target machine:

```bash
cd /path/to/nix-hs-deploy
sudo nixos-rebuild switch --flake .#andromeda
```

### Remote Deployment

From another NixOS machine with flakes:

```bash
nixos-rebuild switch --flake .#andromeda --target-host admin@andromeda --use-remote-sudo
```

### Using nixos-anywhere (Fresh Install)

```bash
nix run github:nix-community/nixos-anywhere -- --flake .#andromeda admin@<ip-address>
```

## GitHub Actions

This repository includes GitHub Actions workflows for CI/CD automation.

### Workflows

| Workflow | File | Description |
|----------|------|-------------|
| **CI** | `ci.yml` | Runs on PRs and pushes - checks flake, builds configs, lints with nixpkgs-lint, validates formatting |
| **Update** | `update.yml` | Weekly automated flake updates with PR creation |
| **Deploy** | `deploy.yml` | Manual deployment to hosts via SSH (runs lint check before deploying) |

### Linting with nixpkgs-lint

The CI pipeline uses [nixpkgs-lint](https://github.com/nix-community/nixpkgs-lint) for semantic linting of Nix files. It detects common issues such as:

- `cmake`, `makeWrapper`, `pkg-config` in `buildInputs` (should be `nativeBuildInputs`)
- Redundant packages from `stdenv` in `nativeBuildInputs`

Linting runs automatically on:
- Every PR and push to `main`/`master`
- Before every deployment (blocks deploy if issues are found)

To run locally:

```bash
nix run github:nix-community/nixpkgs-lint -- .
```

### Setting Up GitHub Actions

#### Required Secrets

Configure these secrets in your repository settings (`Settings > Secrets and variables > Actions`):

| Secret | Description |
|--------|-------------|
| `DEPLOY_SSH_KEY` | Private SSH key for deployment (ed25519 recommended) |
| `DEPLOY_HOST` | Hostname or IP address of the server (e.g., `192.168.1.100`) |
| `DEPLOY_HOST_TAILSCALE` | Tailscale hostname (e.g., `andromeda` for MagicDNS) |
| `DEPLOY_USER` | SSH user for deployment (e.g., `admin`) |
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID (for VPN deployment) |
| `TS_OAUTH_SECRET` | Tailscale OAuth secret (for VPN deployment) |

#### Creating a Deploy Key

```bash
# Generate a new SSH key pair for deployments
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/deploy_key

# Add the public key to your server's authorized_keys
cat ~/.ssh/deploy_key.pub >> ~/.ssh/authorized_keys

# Copy the private key content to DEPLOY_SSH_KEY secret
cat ~/.ssh/deploy_key
```

#### Environment Protection

For additional security, the deploy workflow uses a `production` environment. Configure it in `Settings > Environments`:

1. Create an environment named `production`
2. Add required reviewers (optional)
3. Limit deployment branches to `main`/`master`

### Tailscale VPN Deployment

The deploy workflow supports connecting to your server via Tailscale VPN, which is useful when:
- Your server is behind NAT/firewall without port forwarding
- You want secure deployment without exposing SSH to the internet
- You're deploying from GitHub Actions to a home network

#### Setting Up Tailscale OAuth

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Create a new OAuth client with the following:
   - **Description:** GitHub Actions CI/CD
   - **Tags:** `tag:ci` (create this tag in your ACL policy first)
   - **Scopes:** `devices:write`
3. Copy the Client ID and Secret to GitHub Secrets:
   - `TS_OAUTH_CLIENT_ID`
   - `TS_OAUTH_SECRET`

#### Tailscale ACL Policy

Add this to your Tailscale ACL policy to allow CI runners to connect:

```json
{
  "tagOwners": {
    "tag:ci": ["autogroup:admin"],
    "tag:server": ["autogroup:admin"],
    "tag:media": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:ci"],
      "dst": ["tag:server:22"]
    }
  ]
}
```

#### Using Tailscale Deployment

When triggering a manual deployment:

1. Go to `Actions > Deploy`
2. Click `Run workflow`
3. Select the host and action
4. **Enable "Connect via Tailscale VPN"** (enabled by default)

The workflow will:
1. Connect the GitHub runner to your Tailscale network
2. Use MagicDNS hostname (`DEPLOY_HOST_TAILSCALE`) to reach your server
3. Deploy via the secure Tailscale tunnel
4. Automatically disconnect when done

#### Server-Side Tailscale Configuration

The Andromeda host includes a Tailscale module. Configure it in `hosts/andromeda/default.nix`:

```nix
services.tailscaleConfig = {
  enable = true;
  hostname = "andromeda";
  enableSSH = true;
  acceptRoutes = true;
  tags = [ "tag:server" "tag:media" ];
  # For automatic auth on fresh installs:
  # authKeyFile = "/run/secrets/tailscale-auth-key";
};
```

### Automated Updates

The update workflow runs weekly (Sundays at 3:00 AM UTC) and:

1. Updates all flake inputs (`nix flake update`)
2. Verifies the build still works
3. Creates a Pull Request with the changes

You can also trigger it manually from the Actions tab.

### Manual Deployment

To deploy via GitHub Actions:

1. Go to `Actions > Deploy`
2. Click `Run workflow`
3. Select the host (`andromeda`)
4. Choose the action:
   - `switch` - Build and activate immediately
   - `boot` - Build and activate on next boot
   - `test` - Activate temporarily (reverts on reboot)
   - `dry-run` - Build only, don't deploy

## Service Access

After deployment, access the services at:

| Service      | URL                          | Default Port |
|--------------|------------------------------|--------------|
| Jellyfin     | https://jf.yourdomain.com    | 443 (via Caddy) |
| Jellyfin (direct) | http://andromeda:8096   | 8096         |
| Vaultwarden  | https://vault.yourdomain.com | 443 (via Caddy) |
| Prowlarr     | https://prowlarr.yourdomain.com | 443 (via Caddy) |
| Jellyseerr   | https://request.yourdomain.com | 443 (via Caddy) |
| Streamystats | https://streamystats.yourdomain.com | 443 (via Caddy) |
| Sonarr       | http://andromeda:8989        | 8989         |
| Radarr       | http://andromeda:7878        | 7878         |
| qBittorrent  | http://andromeda:8080        | 8080 (via Gluetun VPN) |

## Caddy Reverse Proxy

Caddy provides automatic HTTPS with Let's Encrypt for Jellyfin. Domain is stored as a secret for security.

### Configuration

```nix
services.caddyProxy = {
  enable = true;
  email = "your-email@example.com";  # For Let's Encrypt notifications

  jellyfin = {
    enable = true;
    domainFile = config.age.secrets.domain-jellyfin.path;
    port = 8096;
  };

  vaultwarden = {
    enable = true;
    domainFile = config.age.secrets.domain-vault.path;
    port = 8222;
    websocketPort = 3012;
  };

  prowlarr = {
    enable = true;
    domainFile = config.age.secrets.domain-prowlarr.path;
    port = 9696;
  };

  jellyseerr = {
    enable = true;
    domainFile = config.age.secrets.domain-request.path;
    port = 5055;
  };

  streamystats = {
    enable = true;
    domainFile = config.age.secrets.domain-streamystats.path;
    port = 3000;
  };

  tailscaleOnly = false;
};
```

### Creating Domain Secrets

```bash
# Enter dev shell
nix develop

# Create Jellyfin domain secret (full domain)
agenix -e secrets/domain-jellyfin.age
# Enter: jf.example.com
```

### DNS Setup

Point your subdomain to your server's public IP:

```
jellyfin.example.com  A  YOUR_PUBLIC_IP
```

Or for Tailscale-only access, use your Tailscale IP or MagicDNS.

### Security Features

- Automatic HTTPS with Let's Encrypt
- HSTS (HTTP Strict Transport Security)
- Security headers (X-Frame-Options, X-Content-Type-Options, etc.)
- WebSocket support for live TV and sync

## Cloudflare DDNS

Automatically updates Cloudflare DNS records when your public IP changes. Essential for home servers with dynamic IP addresses.

### Configuration

```nix
services.cloudflareDdns = {
  enable = true;
  apiTokenFile = config.age.secrets.cloudflare-api-token.path;
  zoneIdFile = config.age.secrets.cloudflare-zone-id.path;

  # Update every 5 minutes
  interval = "5m";

  # IPv4 updates
  ipv4.enable = true;

  # Domains to update
  domains = [
    {
      nameFile = config.age.secrets.cloudflare-jellyfin-domain.path;
      proxied = true;  # Enable Cloudflare proxy (orange cloud)
      type = "A";
      ttl = 1;  # Auto TTL
    }
  ];
};
```

### Creating Cloudflare API Token

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Click **Create Token**
3. Use **Edit zone DNS** template, or create custom with:
   - **Permissions:** Zone → DNS → Edit
   - **Zone Resources:** Include → Specific zone → your domain
4. Copy the token

### Getting Zone ID

1. Go to your domain's overview page in Cloudflare
2. Scroll down to the **API** section on the right
3. Copy the **Zone ID**

### Creating Secrets

```bash
nix develop

# Create API token secret
agenix -e secrets/cloudflare-api-token.age
# Paste your Cloudflare API token

# Create Zone ID secret
agenix -e secrets/cloudflare-zone-id.age
# Paste your Zone ID

# Create full domain secret for DDNS
agenix -e secrets/cloudflare-jellyfin-domain.age
# Enter: jellyfin.example.com
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `interval` | `5m` | How often to check for IP changes |
| `ipv4.enable` | `true` | Update A records |
| `ipv6.enable` | `false` | Update AAAA records |
| `domains[].proxied` | `true` | Use Cloudflare proxy (orange cloud) |
| `domains[].ttl` | `1` | TTL (1 = automatic) |

### Checking Status

```bash
# View service status
systemctl status cloudflare-ddns

# View logs
journalctl -u cloudflare-ddns -f

# Manually trigger update
systemctl start cloudflare-ddns
```

## Vaultwarden

Self-hosted Bitwarden-compatible password manager. All official Bitwarden clients work with Vaultwarden.

### Configuration

```nix
services.vaultwardenConfig = {
  enable = true;
  domainFile = config.age.secrets.domain-vault.path;
  port = 8222;
  websocketPort = 3012;
  signupsAllowed = false;  # Disable after initial setup
  invitationsAllowed = true;
  adminTokenFile = config.age.secrets.vaultwarden-admin-token.path;
};
```

### Creating Admin Token

Generate a secure admin token:

```bash
openssl rand -base64 48
```

Then create the secret:

```bash
agenix -e secrets/vaultwarden-admin-token.age
# Paste the generated token
```

### Admin Panel

Access the admin panel at `https://vault.yourdomain.com/admin` using your admin token.

### Initial Setup

1. Set `signupsAllowed = true` temporarily
2. Deploy and create your account
3. Set `signupsAllowed = false` and redeploy
4. Use invitations for additional users

### Features

- **Automatic backups** - Daily SQLite database backups (7 days retention)
- **WebSocket notifications** - Real-time sync across devices
- **Security hardened** - Runs with minimal privileges
- **HTTPS only** - Via Caddy reverse proxy

### Backup Location

Backups are stored in `/var/lib/vaultwarden/backups/`

```bash
# List backups
ls -la /var/lib/vaultwarden/backups/

# Manual backup
systemctl start vaultwarden-backup
```

## qBittorrent with VPN

Routes qBittorrent traffic through NordVPN using WireGuard via Gluetun. All torrent traffic is encrypted and your real IP is hidden. qBittorrent runs inside Gluetun's network namespace so all traffic goes through the VPN.

### Configuration

```nix
services.qbittorrentVpn = {
  enable = true;
  vpnProvider = "nordvpn";
  vpnType = "wireguard";
  serverCountries = "Romania";
  wireguardPrivateKeyFile = config.age.secrets.gluetun-wireguard-key.path;
  webuiPort = 8080;
  peerPort = 6881;
  downloadDir = "/srv/storage/downloads";
};
```

### Getting NordVPN WireGuard Key

1. Log into [NordVPN](https://my.nordaccount.com/)
2. Go to **Services** → **NordVPN**
3. Click **Set up NordVPN manually**
4. Choose **WireGuard** and generate credentials
5. Copy the private key

```bash
agenix -e secrets/gluetun-wireguard-key.age
# Paste your WireGuard private key
```

### Kill Switch

Gluetun has a built-in kill switch - if the VPN disconnects, all traffic is blocked. Your real IP is never exposed.

### Checking VPN Status

```bash
# Check container status
podman ps | grep -E "gluetun|qbittorrent"

# View VPN logs (shows connection status)
podman logs gluetun

# View qBittorrent logs
podman logs qbittorrent

# Verify your torrent IP (check in qBittorrent or use a torrent IP checker)
```

## Streamystats

Jellyfin analytics and statistics dashboard. Tracks viewing history, popular content, and user activity.

### Configuration

```nix
services.streamystats = {
  enable = true;
  port = 3000;
  sessionSecretFile = config.age.secrets.streamystats-session-secret.path;
  postgres.passwordFile = config.age.secrets.streamystats-postgres-password.path;
};
```

### Creating Secrets

```bash
# Generate session secret
openssl rand -hex 32

agenix -e secrets/streamystats-session-secret.age
# Paste the generated hex string

agenix -e secrets/streamystats-postgres-password.age
# Enter a secure password (e.g., "postgres" for simple setup)
```

### Initial Setup

1. Access Streamystats at `https://streamystats.yourdomain.com`
2. Add your Jellyfin server URL and API key
3. Wait for initial sync to complete

## Configuration

### Media Services

Enable all media services with a single option:

```nix
services.mediaServices = {
  enable = true;
  mediaGroup = "media";
  baseMediaDir = "/srv/storage/media";
  baseDownloadDir = "/srv/storage/downloads";
};
```

#### PostgreSQL Backend (Optional)

For better performance with large media libraries, you can enable a centralized PostgreSQL database for Sonarr, Radarr, and Prowlarr instead of the default SQLite:

```nix
services.mediaServices = {
  enable = true;
  mediaGroup = "media";
  baseMediaDir = "/srv/storage/media";
  baseDownloadDir = "/srv/storage/downloads";
  
  # Enable PostgreSQL backend
  usePostgres = true;
  postgresPasswordFile = config.age.secrets.media-postgres-password.path;
};
```

**Benefits of PostgreSQL over SQLite:**
- Better performance with large libraries (thousands of movies/shows)
- Improved concurrent access handling
- Easier centralized backups
- Reduced disk I/O on the root partition

**Creating the PostgreSQL Password Secret:**

```bash
# Generate a secure password
openssl rand -base64 32 > /tmp/media-postgres-password

# Encrypt with agenix
cd secrets
agenix -e media-postgres-password.age < /tmp/media-postgres-password
rm /tmp/media-postgres-password
```

**Database Details:**
- Host: `localhost` (127.0.0.1)
- Port: `5432`
- Databases created automatically:
  - `sonarr_main`, `sonarr_log` (for Sonarr)
  - `radarr_main`, `radarr_log` (for Radarr)
  - `prowlarr_main`, `prowlarr_log` (for Prowlarr)

**Note:** When migrating from SQLite to PostgreSQL, existing data will need to be manually migrated. The *arr apps will start fresh with empty databases. Consider exporting your configurations before switching.

This automatically enables and configures:
- Jellyfin (port 8096)
- Sonarr (port 8989)
- Radarr (port 7878)
- Prowlarr (port 9696)
- Jellyseerr (port 5055)

### Individual Service Overrides

Each service can be configured individually:

```nix
# Jellyfin with hardware acceleration
services.jellyfinServer = {
  hardwareAcceleration.enable = true;
  hardwareAcceleration.type = "vaapi";  # or "qsv" for Intel QuickSync
};

# Sonarr custom paths
services.sonarrServer = {
  mediaDir = "/custom/path/tv";
  downloadDir = "/custom/path/downloads";
};

# Radarr custom paths
services.radarrServer = {
  mediaDir = "/custom/path/movies";
};
```

### Media Server Options

The media server role supports the following options:

```nix
roles.mediaServer = {
  enable = true;
  mediaDir = "/srv/media";      # Base media directory
  downloadDir = "/srv/downloads"; # Downloads directory
  user = "media";               # Service user
  group = "media";              # Service group
};
```

### Adding Storage Drives

To mount additional storage for media, edit `hardware-configuration.nix`:

```nix
fileSystems."/srv/media" = {
  device = "/dev/disk/by-label/media";
  fsType = "ext4";
  options = [ "nofail" ];
};
```

## Maintenance

### Update the System

#### Via GitHub Actions (Recommended)

1. Merge the automated update PR, or
2. Trigger the update workflow manually

#### Manually

```bash
sudo nixos-rebuild switch --flake .#andromeda --upgrade
```

### Garbage Collection

Automatic garbage collection is enabled weekly. Manual cleanup:

```bash
sudo nix-collect-garbage -d
```

### Check Service Status

```bash
systemctl status jellyfin
systemctl status sonarr
systemctl status radarr
systemctl status prowlarr
systemctl status qbittorrent
```

## Troubleshooting

### View Service Logs

```bash
journalctl -u jellyfin -f
journalctl -u sonarr -f
```

### Check Firewall Rules

```bash
sudo iptables -L -n
```

### Verify Ports are Open

```bash
ss -tlnp | grep -E '(8096|8989|7878|9696|8080)'
```

### GitHub Actions Issues

**Build fails in CI:**
- Check the workflow logs for specific errors
- Ensure `flake.lock` is committed
- Run `nix flake check` locally

**Deploy fails:**
- Verify SSH secrets are correctly configured
- Ensure the deploy key has access to the server
- Check that the server is reachable from GitHub Actions

## Dynamic MOTD

The server displays a dynamic Message of the Day (MOTD) when you SSH in, showing:

- System information (hostname, kernel, CPU, memory, uptime)
- Network addresses (local IP, Tailscale IP)
- Storage usage
- Service status (running/stopped indicators)
- Access links for all services

### Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🌌 Welcome to andromeda
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 System Information
   Kernel:    6.6.30
   CPU:       Intel(R) Core(TM) i5-8400 (6 cores)
   Memory:    4.2G / 16G (26.3%)
   Load:      0.52 0.48 0.45
   Uptime:    5 days, 3 hours

🌐 Network
   Local IP:  192.168.0.26
   Tailscale: 100.64.0.15

💾 Storage
   /:            25G / 100G (25%)
   /srv/storage: 2.1T / 8.0T (26%)

🔧 Services
   ● Jellyfin      ● Sonarr        ● Radarr
   ● Prowlarr      ● Jellyseerr    ● qBittorrent
   ● Caddy         ● Vaultwarden   ● Streamystats
   ● Gluetun VPN   (Public IP: 185.x.x.x)

🔗 Access Links

   Local Network:
   ├─ Jellyfin     http://192.168.0.26:8096
   ├─ Sonarr       http://192.168.0.26:8989
   ├─ Radarr       http://192.168.0.26:7878
   ├─ Prowlarr     http://192.168.0.26:9696
   ├─ Jellyseerr   http://192.168.0.26:5055
   ├─ qBittorrent  http://192.168.0.26:8080
   ├─ Streamystats http://192.168.0.26:3000
   └─ Vaultwarden  http://192.168.0.26:8222

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Configuration

The MOTD is enabled by default. Configure it in `hosts/andromeda/default.nix`:

```nix
services.motd = {
  enable = true;
  
  # Optional: Show external domain links
  externalDomains = {
    Jellyfin = "jf.yourdomain.com";
    Vaultwarden = "vault.yourdomain.com";
    Jellyseerr = "request.yourdomain.com";
    Prowlarr = "prowlarr.yourdomain.com";
    Streamystats = "stats.yourdomain.com";
  };
};
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable dynamic MOTD |
| `externalDomains` | attrs | `{}` | External domain names to display |
| `showStorage` | bool | `true` | Show storage usage |
| `showServices` | bool | `true` | Show service status |
| `showNetworkLinks` | bool | `true` | Show access URLs |
| `extraInfo` | string | `""` | Extra info to display |

## Storage Configuration

### MergerFS Storage Pool

This repository includes a MergerFS module for combining multiple drives into a single storage pool. MergerFS is ideal for media servers because:

- **No parity overhead** - Unlike RAID, all space is usable
- **Mixed drive sizes** - Combine drives of different capacities
- **Easy expansion** - Add or remove drives without rebuilding
- **File integrity** - Files are stored intact on individual drives (easy recovery)
- **Flexible policies** - Control where new files are placed

#### Configuration

Enable MergerFS in your host configuration:

```nix
storage.mergerfs = {
  enable = true;
  poolPath = "/srv/storage";

  # Define your data disks (use /dev/disk/by-id/ for stable names)
  disks = {
    disk1 = {
      device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K0000001";
      fsType = "ext4";
    };
    disk2 = {
      device = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K0000002";
      fsType = "ext4";
    };
  };

  # File creation policy
  policy = {
    create = "epmfs";  # Existing path, most free space
    search = "ff";     # First found (fastest)
  };

  minFreeSpace = "50G";
  cacheMode = "partial";
};
```

#### Finding Disk IDs

```bash
# List all disks with their IDs
ls -la /dev/disk/by-id/

# Or use lsblk with more details
lsblk -o NAME,SIZE,MODEL,SERIAL,PATH
```

#### Create Policies

| Policy | Description |
|--------|-------------|
| `epmfs` | Existing path, most free space (recommended - keeps related files together) |
| `mfs` | Most free space (spreads files across drives) |
| `lfs` | Least free space (fills drives sequentially) |
| `eplfs` | Existing path, least free space |
| `rand` | Random distribution |

#### MergerFS Tools

The module installs `mergerfs-tools` which provides useful utilities:

```bash
# Show space usage per drive
mergerfs.balance /srv/storage

# Find which drive a file is on
mergerfs.ctl /srv/storage

# Consolidate files to fewer drives
mergerfs.consolidate /srv/storage
```

#### Combining with SnapRAID

For parity protection, MergerFS pairs well with SnapRAID:

1. Use MergerFS to pool your data drives
2. Use SnapRAID to create parity across those drives
3. Set `moveOnDelete = true` for SnapRAID compatibility

```nix
storage.mergerfs = {
  enable = true;
  moveOnDelete = true;  # Required for SnapRAID
  # ... rest of config
};
```

## Secrets Management

This repository uses [agenix](https://github.com/ryantm/agenix) for secure secret management. Secrets are encrypted with age and can be safely committed to the repository.

### Quick Start: Generate All Secrets

The easiest way to create all secrets is using the provided script:

```bash
# 1. Copy the example env file
cp .env.secrets.example .env.secrets

# 2. Edit with your actual values
vim .env.secrets

# 3. Run the generator script
./scripts/generate-secrets.sh

# 4. Commit the encrypted secrets
git add secrets/*.age
git commit -m "Add encrypted secrets"
git push
```

### .env.secrets Template

```bash
# Tailscale
TAILSCALE_AUTH_KEY=tskey-auth-xxxxx

# Cloudflare
CLOUDFLARE_API_TOKEN=your-api-token
CLOUDFLARE_ZONE_ID=your-zone-id

# Domains
DOMAIN_JELLYFIN=jf.example.com
DOMAIN_PROWLARR=prowlarr.example.com
DOMAIN_VAULT=vault.example.com
DOMAIN_REQUEST=request.example.com
DOMAIN_AUTH=auth.example.com
DOMAIN_STREAMYSTATS=streamystats.example.com

# Vaultwarden (generate with: openssl rand -base64 48)
VAULTWARDEN_ADMIN_TOKEN=

# VPN (NordVPN WireGuard key)
GLUETUN_WIREGUARD_KEY=

# Streamystats (generate with: openssl rand -hex 32)
STREAMYSTATS_SESSION_SECRET=
STREAMYSTATS_POSTGRES_PASSWORD=postgres
```

⚠️ **Never commit `.env.secrets` to git!** It's already in `.gitignore`.

### How It Works

1. **Encryption**: Secrets are encrypted using SSH public keys (yours and the host's)
2. **Storage**: Encrypted `.age` files are stored in `secrets/` and committed to git
3. **Decryption**: At NixOS activation time, secrets are decrypted using the host's SSH key
4. **Runtime**: Decrypted secrets are placed in `/run/agenix/` with proper permissions

### Project Structure

```
secrets/
├── secrets.nix              # NixOS module declaring secrets & permissions
├── tailscale-auth-key.age   # Encrypted Tailscale auth key
├── cloudflare-api-token.age # Cloudflare API token
├── domain-*.age             # Domain secrets for DDNS/Caddy
└── ...
secrets.nix                  # Defines which keys can decrypt which secrets
```

### Initial Setup

### Manual Secret Creation

If you prefer to create secrets manually:

#### 1. Add Your SSH Public Key

Edit `secrets.nix` and add your SSH public key:

```nix
let
  admin = "ssh-ed25519 AAAA... user@workstation";
  users = [ admin ];
```

#### 2. Add Host SSH Public Key

Get the host's SSH public key:

```bash
# If host is already running
ssh-keyscan andromeda | grep ed25519

# Or from the host directly
cat /etc/ssh/ssh_host_ed25519_key.pub
```

Add it to `secrets.nix`:

```nix
  andromeda = "ssh-ed25519 AAAA... root@andromeda";
  allHosts = [ andromeda ];
```

#### 3. Enter the Development Shell

```bash
nix develop
```

This gives you access to the `agenix` CLI.

### Creating Secrets

#### Create a New Secret

```bash
# Edit/create a secret (opens $EDITOR)
agenix -e secrets/tailscale-auth-key.age

# The secret will be encrypted for all keys listed in secrets.nix
```

#### Re-key All Secrets

After adding or removing keys from `secrets.nix`:

```bash
agenix -r
```

### Available Secrets

| Secret | Description | Used By |
|--------|-------------|---------|
| `tailscale-auth-key.age` | Tailscale auth key for automatic VPN connection | Tailscale service |
| `cloudflare-api-token.age` | Cloudflare API token with DNS edit permissions | Cloudflare DDNS |
| `cloudflare-zone-id.age` | Cloudflare Zone ID for your domain | Cloudflare DDNS |
| `domain-jellyfin.age` | Jellyfin domain (jf.cristeavictor.xyz) | Caddy, DDNS |
| `domain-prowlarr.age` | Prowlarr domain (prowlarr.cristeavictor.xyz) | Caddy, DDNS |
| `domain-vault.age` | Vaultwarden domain (vault.cristeavictor.xyz) | Caddy, DDNS, Vaultwarden |
| `domain-request.age` | Jellyseerr domain (request.cristeavictor.xyz) | Caddy, DDNS |
| `domain-auth.age` | Auth domain (auth.cristeavictor.xyz) | DDNS |
| `domain-streamystats.age` | Streamystats domain (streamystats.cristeavictor.xyz) | Caddy, DDNS |
| `vaultwarden-admin-token.age` | Vaultwarden admin panel token | Vaultwarden |
| `gluetun-wireguard-key.age` | NordVPN WireGuard private key | qBittorrent VPN |
| `streamystats-session-secret.age` | Streamystats session secret | Streamystats |
| `streamystats-postgres-password.age` | Streamystats PostgreSQL password | Streamystats |
| `media-postgres-password.age` | PostgreSQL password for Sonarr, Radarr, Prowlarr | Media PostgreSQL |

### Using Secrets in NixOS Configuration

Secrets are declared in `secrets/secrets.nix`:

```nix
age.secrets = {
  tailscale-auth-key = {
    file = ./tailscale-auth-key.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };
};
```

Reference them in your configuration:

```nix
services.tailscaleConfig = {
  enable = true;
  authKeyFile = config.age.secrets.tailscale-auth-key.path;
};
```

At runtime, the secret is available at `/run/agenix/tailscale-auth-key`.

### Getting a Tailscale Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Configure:
   - **Reusable**: Yes (for rebuilds)
   - **Ephemeral**: No (server should persist)
   - **Tags**: `tag:server` (optional)
   - **Expiration**: Set as needed
4. Copy the key and create the secret:

```bash
agenix -e secrets/tailscale-auth-key.age
# Paste the key, save, and exit
```

### Security Best Practices

1. **Never commit plaintext secrets** - Only `.age` files should be in git
2. **Use separate keys per environment** - Don't share keys between prod/staging
3. **Rotate secrets regularly** - Especially API keys and auth tokens
4. **Limit key access** - Only add necessary public keys to `secrets.nix`
5. **Use short-lived Tailscale keys** - Set expiration when possible

### Troubleshooting

#### "No identity found"

The host's SSH key isn't in `secrets.nix` or doesn't exist:

```bash
# Check host key exists
ls -la /etc/ssh/ssh_host_ed25519_key

# Verify key matches secrets.nix
cat /etc/ssh/ssh_host_ed25519_key.pub
```

#### "Decryption failed"

The secret wasn't encrypted for this host's key:

```bash
# Re-encrypt all secrets with current keys
agenix -r
```

#### Viewing Encrypted Secret Recipients

```bash
# See which keys can decrypt a secret
age-keygen -y secrets/tailscale-auth-key.age
```

## License

MIT
