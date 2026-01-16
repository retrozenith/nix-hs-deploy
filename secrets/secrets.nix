# Agenix secrets declaration for NixOS
#
# This file declares which secrets exist and how they are deployed.
# Secrets are decrypted at NixOS activation time using the host's SSH key.
# Decrypted secrets are placed in /run/agenix/ with the specified permissions.

{ config, lib, ... }:

{
  age.secrets = {
    # ===========================================
    # Tailscale VPN
    # ===========================================
    tailscale-auth-key = {
      file = ./tailscale-auth-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # ===========================================
    # Cloudflare (DDNS)
    # ===========================================
    cloudflare-api-token = {
      file = ./cloudflare-api-token.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    cloudflare-zone-id = {
      file = ./cloudflare-zone-id.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # ===========================================
    # Caddy (Let's Encrypt Email)
    # ===========================================
    caddy-email = {
      file = ./caddy-email.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # ===========================================
    # Domain Names (for Caddy & DDNS)
    # ===========================================
    domain-jellyfin = {
      file = ./domain-jellyfin.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    domain-prowlarr = {
      file = ./domain-prowlarr.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    domain-vault = {
      file = ./domain-vault.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    domain-request = {
      file = ./domain-request.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    domain-auth = {
      file = ./domain-auth.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    domain-streamystats = {
      file = ./domain-streamystats.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # ===========================================
    # Vaultwarden (Password Manager)
    # ===========================================
    vaultwarden-admin-token = {
      file = ./vaultwarden-admin-token.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # ===========================================
    # qBittorrent VPN (Gluetun)
    # ===========================================
    gluetun-wireguard-key = {
      file = ./gluetun-wireguard-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # ===========================================
    # Streamystats (Jellyfin Analytics)
    # ===========================================
    streamystats-session-secret = {
      file = ./streamystats-session-secret.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    streamystats-postgres-password = {
      file = ./streamystats-postgres-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # ===========================================
    # Media PostgreSQL (Sonarr, Radarr, Prowlarr)
    # ===========================================
    media-postgres-password = {
      file = ./media-postgres-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  # SSH key used by the host to decrypt secrets
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];
}
