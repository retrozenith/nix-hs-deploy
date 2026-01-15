# Deployment Guide for Andromeda

## Pre-Deployment Checklist

### 1. Server SSH Host Key

Before secrets can be decrypted on the server, you need its SSH host key.

**If server is already running:**
```bash
ssh-keyscan <server-ip> | grep ed25519
# Example output: <server-ip> ssh-ed25519 AAAA...
```

**Or on the server itself:**
```bash
cat /etc/ssh/ssh_host_ed25519_key.pub
```

Then update `secrets.nix`:
```nix
andromeda = "ssh-ed25519 AAAA... root@andromeda";
```

### 2. Create Secrets

```bash
# Copy the template
cp env.secrets.example .env.secrets

# Edit with your values
vim .env.secrets

# Generate encrypted secrets
./scripts/generate-secrets.sh
```

### 3. Configure Hardware

Edit `hosts/andromeda/hardware-configuration.nix` with output from:
```bash
nixos-generate-config --show-hardware-config
```

### 4. Configure MergerFS Disks (if using)

Find your disk IDs:
```bash
ls -la /dev/disk/by-id/ | grep -v part
```

Update `hosts/andromeda/default.nix`:
```nix
storage.mergerfs.disks = {
  disk1 = {
    device = "/dev/disk/by-id/ata-WDC_...";
    fsType = "ext4";
  };
  # ...
};
```

### 5. Update Email for Let's Encrypt

In `hosts/andromeda/default.nix`, change:
```nix
services.caddyProxy.email = "your-real-email@example.com";
```

---

## Secrets Required

| Secret | How to Get |
|--------|------------|
| `TAILSCALE_AUTH_KEY` | [Tailscale Admin](https://login.tailscale.com/admin/settings/keys) |
| `CLOUDFLARE_API_TOKEN` | [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens) |
| `CLOUDFLARE_ZONE_ID` | Domain Overview page in Cloudflare |
| `VAULTWARDEN_ADMIN_TOKEN` | `openssl rand -base64 48` |
| `GLUETUN_WIREGUARD_KEY` | [NordVPN Manual Setup](https://my.nordaccount.com/) → WireGuard |
| `STREAMYSTATS_SESSION_SECRET` | `openssl rand -hex 32` |
| `STREAMYSTATS_POSTGRES_PASSWORD` | Any secure password |

---

## GitHub Secrets (for CI/CD)

Configure in: `Settings → Secrets and variables → Actions`

| Secret | Value |
|--------|-------|
| `DEPLOY_SSH_KEY` | Private key from `~/.ssh/andromeda_deploy` |
| `DEPLOY_HOST` | `192.168.0.26` (or your server IP) |
| `DEPLOY_HOST_TAILSCALE` | `andromeda` (Tailscale hostname) |
| `DEPLOY_USER` | `admin` |
| `TS_OAUTH_CLIENT_ID` | From Tailscale OAuth |
| `TS_OAUTH_SECRET` | From Tailscale OAuth |

---

## Deploy

### Option A: Via GitHub Actions (Recommended)

1. Push your changes:
   ```bash
   git add .
   git commit -m "Ready for deployment"
   git push
   ```

2. Go to **Actions → Deploy → Run workflow**

3. Select options and deploy

### Option B: Direct Deployment

```bash
# From local machine with Nix
nixos-rebuild switch --flake .#andromeda \
  --target-host admin@192.168.0.26 \
  --use-remote-sudo
```

### Option C: On the Server

```bash
cd /path/to/nix-hs-deploy
sudo nixos-rebuild switch --flake .#andromeda
```

---

## Post-Deployment

### Verify Services

```bash
# Check all services
systemctl status jellyfin sonarr radarr prowlarr jellyseerr

# Check containers
podman ps

# Check Caddy
systemctl status caddy
journalctl -u caddy -f
```

### Access Services

| Service | URL |
|---------|-----|
| Jellyfin | https://jf.yourdomain.com |
| Vaultwarden | https://vault.yourdomain.com |
| Prowlarr | https://prowlarr.yourdomain.com |
| Jellyseerr | https://request.yourdomain.com |
| Streamystats | https://streamystats.yourdomain.com |
| qBittorrent | http://192.168.0.26:8080 |
| Sonarr | http://192.168.0.26:8989 |
| Radarr | http://192.168.0.26:7878 |

### Initial Setup Steps

1. **Vaultwarden**: 
   - Temporarily set `signupsAllowed = true`, redeploy
   - Create your account
   - Set `signupsAllowed = false`, redeploy

2. **Jellyfin**: 
   - Complete setup wizard
   - Add media libraries pointing to `/srv/storage/media/*`

3. **Sonarr/Radarr**: 
   - Add download client (qBittorrent at `gluetun:8080`)
   - Configure root folders

4. **Prowlarr**: 
   - Add indexers
   - Sync with Sonarr/Radarr

5. **Jellyseerr**: 
   - Connect to Jellyfin
   - Connect to Sonarr/Radarr

6. **Streamystats**:
   - Add Jellyfin server URL and API key

---

## Troubleshooting

### Secret Decryption Failed

```bash
# Check if host key is correct
cat /etc/ssh/ssh_host_ed25519_key.pub

# Re-encrypt secrets with correct key
agenix -r
```

### Service Won't Start

```bash
journalctl -u <service-name> -f
```

### VPN Not Working

```bash
podman logs gluetun
# Check for connection errors
```

### Caddy Certificate Issues

```bash
journalctl -u caddy -f
# Check for ACME errors

# Verify DNS is pointing to your IP
dig +short jf.yourdomain.com
```
