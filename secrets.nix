# Agenix secrets encryption configuration
#
# This file defines which SSH public keys can decrypt which secrets.
# Secrets are encrypted using `age` and stored as .age files.
#
# Usage:
#   1. Update the SSH public keys below with real keys
#   2. Run: ./scripts/generate-secrets.sh
#   Or manually: agenix -e secrets/<secret-name>.age
#
# To re-encrypt all secrets after adding/removing keys:
#   agenix -r

let
  # ===========================================
  # SSH Public Keys
  # ===========================================

  # User key (for encrypting/editing secrets)
  # This is the deploy key used for CI/CD and manual management
  admin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILpgI8QYYV6UspNyqa1PfDd0LafyR8ebKqky56z6YJd3 andromeda-deploy";

  # Host key (for decrypting secrets at runtime)
  # Get this from the server: cat /etc/ssh/ssh_host_ed25519_key.pub
  # Or remotely: ssh-keyscan <server-ip> | grep ed25519
  #
  # TODO: Replace with actual server host key before first deployment
  andromeda = "ssh-ed25519 AAAA... root@andromeda";

  # Key groups
  users = [ admin ];
  hosts = [ andromeda ];
  allKeys = users ++ hosts;

in
{
  # ===========================================
  # Tailscale VPN
  # ===========================================
  "tailscale-auth-key.age".publicKeys = allKeys;

  # ===========================================
  # Cloudflare (DDNS)
  # ===========================================
  "cloudflare-api-token.age".publicKeys = allKeys;
  "cloudflare-zone-id.age".publicKeys = allKeys;

  # ===========================================
  # Domain Names (for Caddy & DDNS)
  # ===========================================
  "domain-jellyfin.age".publicKeys = allKeys;
  "domain-prowlarr.age".publicKeys = allKeys;
  "domain-vault.age".publicKeys = allKeys;
  "domain-request.age".publicKeys = allKeys;
  "domain-auth.age".publicKeys = allKeys;
  "domain-streamystats.age".publicKeys = allKeys;

  # ===========================================
  # Vaultwarden (Password Manager)
  # ===========================================
  "vaultwarden-admin-token.age".publicKeys = allKeys;

  # ===========================================
  # qBittorrent VPN (Gluetun)
  # ===========================================
  "gluetun-wireguard-key.age".publicKeys = allKeys;

  # ===========================================
  # Streamystats (Jellyfin Analytics)
  # ===========================================
  "streamystats-session-secret.age".publicKeys = allKeys;
  "streamystats-postgres-password.age".publicKeys = allKeys;
}
