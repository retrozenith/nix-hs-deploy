# Vaultwarden - Self-hosted Bitwarden compatible password manager
#
# Provides a lightweight, self-hosted implementation of the Bitwarden API
# Compatible with official Bitwarden clients

{ config, pkgs, lib, ... }:

{
  options.services.vaultwardenConfig = {
    enable = lib.mkEnableOption "Vaultwarden password manager";

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Domain for Vaultwarden (e.g., https://vault.example.com)";
    };

    domainFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing domain (alternative to domain option)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8222;
      description = "Port for Vaultwarden web interface";
    };

    websocketPort = lib.mkOption {
      type = lib.types.port;
      default = 3012;
      description = "Port for Vaultwarden WebSocket notifications";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/vaultwarden";
      description = "Directory to store Vaultwarden data";
    };

    signupsAllowed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow new user signups (disable after initial setup)";
    };

    invitationsAllowed = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow invited users to signup";
    };

    showPasswordHint = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show password hints (security risk, not recommended)";
    };

    adminTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing admin panel token (leave null to disable admin panel)";
    };

    smtp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable SMTP for email notifications";
      };

      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SMTP server hostname";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 587;
        description = "SMTP server port";
      };

      from = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Email from address";
      };

      fromName = lib.mkOption {
        type = lib.types.str;
        default = "Vaultwarden";
        description = "Email from name";
      };

      security = lib.mkOption {
        type = lib.types.enum [ "starttls" "force_tls" "off" ];
        default = "starttls";
        description = "SMTP security mode";
      };

      usernameFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing SMTP username";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing SMTP password";
      };
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to environment file with additional secrets";
    };
  };

  config = lib.mkIf config.services.vaultwardenConfig.enable {
    # Use the built-in NixOS Vaultwarden service
    services.vaultwarden = {
      enable = true;

      dbBackend = "sqlite";

      config = {
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = config.services.vaultwardenConfig.port;

        WEBSOCKET_ENABLED = true;
        WEBSOCKET_ADDRESS = "127.0.0.1";
        WEBSOCKET_PORT = config.services.vaultwardenConfig.websocketPort;

        SIGNUPS_ALLOWED = config.services.vaultwardenConfig.signupsAllowed;
        INVITATIONS_ALLOWED = config.services.vaultwardenConfig.invitationsAllowed;
        SHOW_PASSWORD_HINT = config.services.vaultwardenConfig.showPasswordHint;

        # Security settings
        PASSWORD_ITERATIONS = 600000;
        DISABLE_ICON_DOWNLOAD = false;
        ICON_CACHE_TTL = 2592000; # 30 days
        ICON_CACHE_NEGTTL = 259200; # 3 days

        # Logging
        LOG_LEVEL = "info";
        EXTENDED_LOGGING = true;
      } // lib.optionalAttrs (config.services.vaultwardenConfig.domain != null) {
        DOMAIN = config.services.vaultwardenConfig.domain;
      } // lib.optionalAttrs config.services.vaultwardenConfig.smtp.enable {
        SMTP_HOST = config.services.vaultwardenConfig.smtp.host;
        SMTP_PORT = config.services.vaultwardenConfig.smtp.port;
        SMTP_FROM = config.services.vaultwardenConfig.smtp.from;
        SMTP_FROM_NAME = config.services.vaultwardenConfig.smtp.fromName;
        SMTP_SECURITY = config.services.vaultwardenConfig.smtp.security;
      };

      # Use generated env file if secrets are configured, otherwise use user-provided environmentFile
      environmentFile =
        if (config.services.vaultwardenConfig.domainFile != null ||
          config.services.vaultwardenConfig.adminTokenFile != null ||
          (config.services.vaultwardenConfig.smtp.enable && config.services.vaultwardenConfig.smtp.usernameFile != null))
        then "/run/vaultwarden/env"
        else config.services.vaultwardenConfig.environmentFile;
    };

    systemd = {
      # Generate environment file from secrets if needed
      services.vaultwarden-env-generator = lib.mkIf
        (
          config.services.vaultwardenConfig.domainFile != null ||
          config.services.vaultwardenConfig.adminTokenFile != null ||
          (config.services.vaultwardenConfig.smtp.enable && config.services.vaultwardenConfig.smtp.usernameFile != null)
        )
        {
          description = "Generate Vaultwarden environment from secrets";
          before = [ "vaultwarden.service" ];
          requiredBy = [ "vaultwarden.service" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";
            Group = "root";
          };

          script =
            let
              cfg = config.services.vaultwardenConfig;
            in
            ''
              set -euo pipefail

              ENV_FILE="/run/vaultwarden/env"
              mkdir -p /run/vaultwarden
              chmod 750 /run/vaultwarden

              # Start with empty file
              echo "# Auto-generated Vaultwarden environment" > "$ENV_FILE"

              ${lib.optionalString (cfg.domainFile != null) ''
                DOMAIN=$(cat ${cfg.domainFile})
                echo "DOMAIN=https://$DOMAIN" >> "$ENV_FILE"
              ''}

              ${lib.optionalString (cfg.adminTokenFile != null) ''
                ADMIN_TOKEN=$(cat ${cfg.adminTokenFile})
                echo "ADMIN_TOKEN=$ADMIN_TOKEN" >> "$ENV_FILE"
              ''}

              ${lib.optionalString (cfg.smtp.enable && cfg.smtp.usernameFile != null) ''
                SMTP_USERNAME=$(cat ${cfg.smtp.usernameFile})
                echo "SMTP_USERNAME=$SMTP_USERNAME" >> "$ENV_FILE"
              ''}

              ${lib.optionalString (cfg.smtp.enable && cfg.smtp.passwordFile != null) ''
                SMTP_PASSWORD=$(cat ${cfg.smtp.passwordFile})
                echo "SMTP_PASSWORD=$SMTP_PASSWORD" >> "$ENV_FILE"
              ''}

              chmod 400 "$ENV_FILE"
              chown vaultwarden:vaultwarden "$ENV_FILE"
            '';
        };

      # Create data directory
      tmpfiles.rules = [
        "d ${config.services.vaultwardenConfig.dataDir} 0750 vaultwarden vaultwarden -"
      ];

      # Firewall - only open if not behind reverse proxy
      # Typically you'd use Caddy in front, so these stay closed
      # networking.firewall.allowedTCPPorts = [
      #   config.services.vaultwardenConfig.port
      #   config.services.vaultwardenConfig.websocketPort
      # ];

      # Backup service for Vaultwarden data
      services.vaultwarden-backup = {
        description = "Backup Vaultwarden database";
        after = [ "vaultwarden.service" ];

        serviceConfig = {
          Type = "oneshot";
          User = "vaultwarden";
          Group = "vaultwarden";
        };

        script = ''
          set -euo pipefail
          BACKUP_DIR="${config.services.vaultwardenConfig.dataDir}/backups"
          mkdir -p "$BACKUP_DIR"

          # Backup SQLite database
          ${pkgs.sqlite}/bin/sqlite3 "${config.services.vaultwardenConfig.dataDir}/db.sqlite3" ".backup '$BACKUP_DIR/db-$(date +%Y%m%d-%H%M%S).sqlite3'"

          # Keep only last 7 backups
          ls -t "$BACKUP_DIR"/db-*.sqlite3 2>/dev/null | tail -n +8 | xargs -r rm
        '';
      };

      # Daily backup timer
      timers.vaultwarden-backup = {
        description = "Daily Vaultwarden backup";
        wantedBy = [ "timers.target" ];

        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
      };
    };
  };
}
