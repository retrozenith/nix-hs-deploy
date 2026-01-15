# Prowlarr - Indexer manager for Sonarr, Radarr, etc.
# https://prowlarr.com/
#
# Manages torrent and usenet indexers in one place
# Syncs with Sonarr, Radarr, and other *arr apps
#
# PostgreSQL support via environment variables:
# - PROWLARR__POSTGRES__HOST
# - PROWLARR__POSTGRES__PORT
# - PROWLARR__POSTGRES__USER
# - PROWLARR__POSTGRES__PASSWORD
# - PROWLARR__POSTGRES__MAINDB
# - PROWLARR__POSTGRES__LOGDB

{ config, pkgs, lib, ... }:

let
  cfg = config.services.prowlarrServer;
  pgCfg = config.services.mediaPostgres;
  usePostgres = cfg.postgres.enable && pgCfg.enable;
in
{
  options.services.prowlarrServer = {
    enable = lib.mkEnableOption "Prowlarr indexer manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9696;
      description = "Port for Prowlarr web interface";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/prowlarr";
      description = "Directory for Prowlarr configuration and database";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall port for Prowlarr";
    };

    postgres = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use PostgreSQL instead of SQLite (requires services.mediaPostgres.enable)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Use the built-in NixOS Prowlarr service
    services.prowlarr = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 prowlarr prowlarr -"
    ];

    # PostgreSQL environment variables for Prowlarr
    systemd.services.prowlarr.environment = lib.mkIf usePostgres {
      PROWLARR__POSTGRES__HOST = pgCfg.host;
      PROWLARR__POSTGRES__PORT = toString pgCfg.port;
      PROWLARR__POSTGRES__USER = pgCfg.prowlarr.user;
      PROWLARR__POSTGRES__MAINDB = pgCfg.prowlarr.mainDb;
      PROWLARR__POSTGRES__LOGDB = pgCfg.prowlarr.logDb;
    };

    # Load password from file via EnvironmentFile
    systemd.services.prowlarr.serviceConfig = lib.mkIf usePostgres {
      ExecStartPre = lib.mkBefore [
        "+${pkgs.writeShellScript "prowlarr-postgres-env" ''
          mkdir -p /run/prowlarr
          echo "PROWLARR__POSTGRES__PASSWORD=$(cat ${pgCfg.passwordFile})" > /run/prowlarr/postgres.env
          chown prowlarr:prowlarr /run/prowlarr/postgres.env
          chmod 400 /run/prowlarr/postgres.env
        ''}"
      ];
      EnvironmentFile = lib.mkIf (pgCfg.passwordFile != null) "/run/prowlarr/postgres.env";
    };

    # Ensure PostgreSQL is ready before Prowlarr starts
    systemd.services.prowlarr.after = lib.mkIf usePostgres [ "postgresql.service" "media-postgres-setup.service" ];
    systemd.services.prowlarr.requires = lib.mkIf usePostgres [ "postgresql.service" ];

    # Firewall configuration
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.port
    ];
  };
}
