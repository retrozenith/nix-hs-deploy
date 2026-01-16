# Caddy reverse proxy configuration for media services
# Provides automatic HTTPS and reverse proxying for services
#
# Domain configuration is read from agenix secrets for security

{ config, pkgs, lib, ... }:

{
  options.services.caddyProxy = {
    enable = lib.mkEnableOption "Caddy reverse proxy for media services";

    email = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email for Let's Encrypt certificate notifications (use emailFile for secrets)";
    };

    emailFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing email for Let's Encrypt (agenix secret)";
    };

    jellyfin = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Jellyfin reverse proxy";
      };

      domainFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing full Jellyfin domain (e.g., jf.example.com)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8096;
        description = "Jellyfin backend port";
      };
    };

    vaultwarden = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Vaultwarden reverse proxy";
      };

      domainFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing full Vaultwarden domain (e.g., vault.example.com)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8222;
        description = "Vaultwarden backend port";
      };

      websocketPort = lib.mkOption {
        type = lib.types.port;
        default = 3012;
        description = "Vaultwarden WebSocket port";
      };
    };

    prowlarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Prowlarr reverse proxy";
      };

      domainFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing full Prowlarr domain (e.g., prowlarr.example.com)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 9696;
        description = "Prowlarr backend port";
      };
    };

    jellyseerr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Jellyseerr reverse proxy";
      };

      domainFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing full Jellyseerr domain (e.g., request.example.com)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5055;
        description = "Jellyseerr backend port";
      };
    };

    streamystats = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Streamystats reverse proxy";
      };

      domainFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing full Streamystats domain (e.g., streamystats.example.com)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "Streamystats backend port";
      };
    };

    tailscaleOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Only allow access from Tailscale network (uses tailscale HTTPS certs)";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra Caddy configuration to append";
    };
  };

  config = lib.mkIf config.services.caddyProxy.enable {
    # Install Caddy
    services.caddy = {
      enable = true;

      # Global Caddy configuration
      globalConfig = ''
        ${lib.optionalString (config.services.caddyProxy.email != null) ''
          email ${config.services.caddyProxy.email}
        ''}
        ${lib.optionalString config.services.caddyProxy.tailscaleOnly ''
          # Use Tailscale HTTPS certificates
          auto_https disable_redirects
        ''}
      '';

      # Virtual hosts are configured via extraConfig to support secrets
      extraConfig = "";
    };

    systemd = {
      # Systemd service to generate Caddy config from secrets
      services.caddy-config-generator = {
        description = "Generate Caddy configuration from secrets";
        before = [ "caddy.service" ];
        requiredBy = [ "caddy.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Group = "root";
        };

        script = let
          cfg = config.services.caddyProxy;
        in ''
          set -euo pipefail

          # Read email from secret file if configured
          ${lib.optionalString (cfg.emailFile != null) ''
            CADDY_EMAIL=$(cat ${cfg.emailFile})
          ''}
          ${lib.optionalString (cfg.email != null && cfg.emailFile == null) ''
            CADDY_EMAIL="${cfg.email}"
          ''}

          # Read domains from secrets
          ${lib.optionalString (cfg.jellyfin.enable && cfg.jellyfin.domainFile != null) ''
            JELLYFIN_HOST=$(cat ${cfg.jellyfin.domainFile})
          ''}

          ${lib.optionalString (cfg.vaultwarden.enable && cfg.vaultwarden.domainFile != null) ''
            VAULTWARDEN_HOST=$(cat ${cfg.vaultwarden.domainFile})
          ''}

          ${lib.optionalString (cfg.prowlarr.enable && cfg.prowlarr.domainFile != null) ''
            PROWLARR_HOST=$(cat ${cfg.prowlarr.domainFile})
          ''}

          ${lib.optionalString (cfg.jellyseerr.enable && cfg.jellyseerr.domainFile != null) ''
            JELLYSEERR_HOST=$(cat ${cfg.jellyseerr.domainFile})
          ''}

          ${lib.optionalString (cfg.streamystats.enable && cfg.streamystats.domainFile != null) ''
            STREAMYSTATS_HOST=$(cat ${cfg.streamystats.domainFile})
          ''}

          # Generate Caddyfile
          cat > /etc/caddy/Caddyfile.generated << ENDOFFILE
          # Auto-generated Caddy configuration
          # Do not edit manually - managed by NixOS

          ${lib.optionalString (cfg.emailFile != null || cfg.email != null) ''
          {
              email $CADDY_EMAIL
          }
          ''}

          # Common security headers snippet
          (security_headers) {
              header {
                  Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
                  X-Frame-Options "SAMEORIGIN"
                  X-Content-Type-Options "nosniff"
                  Referrer-Policy "strict-origin-when-cross-origin"
                  X-XSS-Protection "1; mode=block"
                  -Server
              }
          }

          ${lib.optionalString (cfg.jellyfin.enable && cfg.jellyfin.domainFile != null) ''
          # Jellyfin - Media Server
          $JELLYFIN_HOST {
              import security_headers

              reverse_proxy localhost:${toString cfg.jellyfin.port} {
                  flush_interval -1
                  header_up X-Real-IP {remote_host}
                  header_up X-Forwarded-For {remote_host}
                  header_up X-Forwarded-Proto {scheme}
                  header_up X-Forwarded-Host {host}
                  header_up Connection {>Connection}
                  header_up Upgrade {>Upgrade}
              }

              @websockets {
                  header Connection *Upgrade*
                  header Upgrade websocket
              }
              reverse_proxy @websockets localhost:${toString cfg.jellyfin.port}

              log {
                  output file /var/log/caddy/jellyfin.log {
                      roll_size 10mb
                      roll_keep 5
                  }
              }
          }
          ''}

          ${lib.optionalString (cfg.vaultwarden.enable && cfg.vaultwarden.domainFile != null) ''
          # Vaultwarden - Password Manager
          $VAULTWARDEN_HOST {
              import security_headers

              # Additional security for Vaultwarden
              header {
                  X-Robots-Tag "noindex, nofollow"
              }

              # Notifications WebSocket
              reverse_proxy /notifications/hub localhost:${toString cfg.vaultwarden.websocketPort}

              # API and Web UI
              reverse_proxy localhost:${toString cfg.vaultwarden.port} {
                  header_up X-Real-IP {remote_host}
                  header_up X-Forwarded-For {remote_host}
                  header_up X-Forwarded-Proto {scheme}
              }

              log {
                  output file /var/log/caddy/vaultwarden.log {
                      roll_size 10mb
                      roll_keep 5
                  }
              }
          }
          ''}

          ${lib.optionalString (cfg.prowlarr.enable && cfg.prowlarr.domainFile != null) ''
          # Prowlarr - Indexer Manager
          $PROWLARR_HOST {
              import security_headers

              reverse_proxy localhost:${toString cfg.prowlarr.port} {
                  header_up X-Real-IP {remote_host}
                  header_up X-Forwarded-For {remote_host}
                  header_up X-Forwarded-Proto {scheme}
              }

              log {
                  output file /var/log/caddy/prowlarr.log {
                      roll_size 10mb
                      roll_keep 5
                  }
              }
          }
          ''}

          ${lib.optionalString (cfg.jellyseerr.enable && cfg.jellyseerr.domainFile != null) ''
          # Jellyseerr - Request Management
          $JELLYSEERR_HOST {
              import security_headers

              reverse_proxy localhost:${toString cfg.jellyseerr.port} {
                  header_up X-Real-IP {remote_host}
                  header_up X-Forwarded-For {remote_host}
                  header_up X-Forwarded-Proto {scheme}
              }

              log {
                  output file /var/log/caddy/jellyseerr.log {
                      roll_size 10mb
                      roll_keep 5
                  }
              }
          }
          ''}

          ${lib.optionalString (cfg.streamystats.enable && cfg.streamystats.domainFile != null) ''
          # Streamystats - Jellyfin Analytics
          $STREAMYSTATS_HOST {
              import security_headers

              reverse_proxy localhost:${toString cfg.streamystats.port} {
                  header_up X-Real-IP {remote_host}
                  header_up X-Forwarded-For {remote_host}
                  header_up X-Forwarded-Proto {scheme}
              }

              log {
                  output file /var/log/caddy/streamystats.log {
                      roll_size 10mb
                      roll_keep 5
                  }
              }
          }
          ''}

          ${cfg.extraConfig}
          ENDOFFILE

          # Set proper permissions
          chmod 644 /etc/caddy/Caddyfile.generated
          chown caddy:caddy /etc/caddy/Caddyfile.generated
        '';
      };

      # Override Caddy service to use generated config
      services.caddy = {
        serviceConfig = {
          ExecStart = lib.mkForce "${pkgs.caddy}/bin/caddy run --config /etc/caddy/Caddyfile.generated --adapter caddyfile";
          ExecReload = lib.mkForce "${pkgs.caddy}/bin/caddy reload --config /etc/caddy/Caddyfile.generated --adapter caddyfile";
        };
      };

      # Create log directory
      tmpfiles.rules = [
        "d /var/log/caddy 0755 caddy caddy -"
        "d /etc/caddy 0755 caddy caddy -"
      ];
    };

    # Firewall rules
    networking.firewall.allowedTCPPorts = [
      80   # HTTP (for ACME challenges and redirects)
      443  # HTTPS
    ];
  };
}
