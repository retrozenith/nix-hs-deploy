# Sonarr - TV show management and automation
# https://sonarr.tv/
#
# Automatically downloads TV shows via Usenet and BitTorrent
#
# PostgreSQL support via environment variables:
# - SONARR__POSTGRES__HOST
# - SONARR__POSTGRES__PORT
# - SONARR__POSTGRES__USER
# - SONARR__POSTGRES__PASSWORD
# - SONARR__POSTGRES__MAINDB
# - SONARR__POSTGRES__LOGDB

{ config, pkgs, lib, ... }:

let
  cfg = config.services.sonarrServer;
  pgCfg = config.services.mediaPostgres;
  usePostgres = cfg.postgres.enable && pgCfg.enable;
in
{
  options.services.sonarrServer = {
    enable = lib.mkEnableOption "Sonarr TV show manager";

    user = lib.mkOption {
      type = lib.types.str;
      default = "sonarr";
      description = "User to run Sonarr as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Group to run Sonarr as";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8989;
      description = "Port for Sonarr web interface";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/sonarr";
      description = "Directory for Sonarr configuration and database";
    };

    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/media/tv";
      description = "Directory for TV show library";
    };

    downloadDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/downloads";
      description = "Directory for downloads";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall port for Sonarr";
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
    # Use the built-in NixOS Sonarr service
    services.sonarr = {
      enable = true;
      inherit (cfg) user group dataDir openFirewall;
    };

    # Create user if using default
    users.users.${cfg.user} = lib.mkIf (cfg.user == "sonarr") {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.dataDir;
    };

    # Ensure media group exists
    users.groups.${cfg.group} = { };

    # Create directories with proper permissions and configure systemd
    systemd = {
      tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
        "d ${cfg.mediaDir} 0775 ${cfg.user} ${cfg.group} -"
      ];

      services.sonarr = {
        # PostgreSQL environment variables for Sonarr
        environment = lib.mkIf usePostgres {
          SONARR__POSTGRES__HOST = pgCfg.host;
          SONARR__POSTGRES__PORT = toString pgCfg.port;
          SONARR__POSTGRES__USER = pgCfg.sonarr.user;
          SONARR__POSTGRES__MAINDB = pgCfg.sonarr.mainDb;
          SONARR__POSTGRES__LOGDB = pgCfg.sonarr.logDb;
        };

        # Load password from file via EnvironmentFile
        serviceConfig = lib.mkIf usePostgres {
          ExecStartPre = lib.mkBefore [
            "+${pkgs.writeShellScript "sonarr-postgres-env" ''
              mkdir -p /run/sonarr
              echo "SONARR__POSTGRES__PASSWORD=$(cat ${pgCfg.passwordFile})" > /run/sonarr/postgres.env
              chown ${cfg.user}:${cfg.group} /run/sonarr/postgres.env
              chmod 400 /run/sonarr/postgres.env
            ''}"
          ];
          EnvironmentFile = lib.mkIf (pgCfg.passwordFile != null) "/run/sonarr/postgres.env";
        };

        # Ensure PostgreSQL is ready before Sonarr starts
        after = lib.mkIf usePostgres [ "postgresql.service" "media-postgres-setup.service" ];
        requires = lib.mkIf usePostgres [ "postgresql.service" ];
      };
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.port
    ];
  };
}
