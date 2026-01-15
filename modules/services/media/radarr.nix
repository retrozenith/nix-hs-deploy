# Radarr - Movie management and automation
# https://radarr.video/
#
# Automatically downloads movies via Usenet and BitTorrent
#
# PostgreSQL support via environment variables:
# - RADARR__POSTGRES__HOST
# - RADARR__POSTGRES__PORT
# - RADARR__POSTGRES__USER
# - RADARR__POSTGRES__PASSWORD
# - RADARR__POSTGRES__MAINDB
# - RADARR__POSTGRES__LOGDB

{ config, pkgs, lib, ... }:

let
  cfg = config.services.radarrServer;
  pgCfg = config.services.mediaPostgres;
  usePostgres = cfg.postgres.enable && pgCfg.enable;
in
{
  options.services.radarrServer = {
    enable = lib.mkEnableOption "Radarr movie manager";

    user = lib.mkOption {
      type = lib.types.str;
      default = "radarr";
      description = "User to run Radarr as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Group to run Radarr as";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7878;
      description = "Port for Radarr web interface";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/radarr";
      description = "Directory for Radarr configuration and database";
    };

    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/media/movies";
      description = "Directory for movie library";
    };

    downloadDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/downloads";
      description = "Directory for downloads";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall port for Radarr";
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
    # Use the built-in NixOS Radarr service
    services.radarr = {
      enable = true;
      user = cfg.user;
      group = cfg.group;
      dataDir = cfg.dataDir;
      openFirewall = cfg.openFirewall;
    };

    # Create user if using default
    users.users.${cfg.user} = lib.mkIf (cfg.user == "radarr") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
    };

    # Ensure media group exists
    users.groups.${cfg.group} = { };

    # Create directories with proper permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.mediaDir} 0775 ${cfg.user} ${cfg.group} -"
    ];

    # PostgreSQL environment variables for Radarr
    systemd.services.radarr.environment = lib.mkIf usePostgres {
      RADARR__POSTGRES__HOST = pgCfg.host;
      RADARR__POSTGRES__PORT = toString pgCfg.port;
      RADARR__POSTGRES__USER = pgCfg.radarr.user;
      RADARR__POSTGRES__MAINDB = pgCfg.radarr.mainDb;
      RADARR__POSTGRES__LOGDB = pgCfg.radarr.logDb;
    };

    # Load password from file via EnvironmentFile
    systemd.services.radarr.serviceConfig = lib.mkIf usePostgres {
      ExecStartPre = lib.mkBefore [
        "+${pkgs.writeShellScript "radarr-postgres-env" ''
          mkdir -p /run/radarr
          echo "RADARR__POSTGRES__PASSWORD=$(cat ${pgCfg.passwordFile})" > /run/radarr/postgres.env
          chown ${cfg.user}:${cfg.group} /run/radarr/postgres.env
          chmod 400 /run/radarr/postgres.env
        ''}"
      ];
      EnvironmentFile = lib.mkIf (pgCfg.passwordFile != null) "/run/radarr/postgres.env";
    };

    # Ensure PostgreSQL is ready before Radarr starts
    systemd.services.radarr.after = lib.mkIf usePostgres [ "postgresql.service" "media-postgres-setup.service" ];
    systemd.services.radarr.requires = lib.mkIf usePostgres [ "postgresql.service" ];

    # Firewall configuration
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.port
    ];
  };
}
