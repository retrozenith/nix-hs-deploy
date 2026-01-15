# Centralized PostgreSQL database for media services
# Provides a shared PostgreSQL instance for Sonarr, Radarr, and Prowlarr
#
# Benefits of PostgreSQL over SQLite:
# - Better performance with large libraries
# - Concurrent access handling
# - Easier backups and replication
# - Reduced disk I/O
#
# Environment variables format for *arr apps:
# - APPNAME__POSTGRES__HOST
# - APPNAME__POSTGRES__PORT
# - APPNAME__POSTGRES__USER
# - APPNAME__POSTGRES__PASSWORD
# - APPNAME__POSTGRES__MAINDB
# - APPNAME__POSTGRES__LOGDB

{ config, pkgs, lib, ... }:

let
  cfg = config.services.mediaPostgres;
in
{
  options.services.mediaPostgres = {
    enable = lib.mkEnableOption "centralized PostgreSQL for media services";

    host = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "PostgreSQL host address";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5432;
      description = "PostgreSQL port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/postgresql";
      description = "PostgreSQL data directory";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing the PostgreSQL password for media services";
    };

    # Per-service database configuration
    sonarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create databases for Sonarr";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "sonarr";
        description = "PostgreSQL user for Sonarr";
      };

      mainDb = lib.mkOption {
        type = lib.types.str;
        default = "sonarr_main";
        description = "Main database name for Sonarr";
      };

      logDb = lib.mkOption {
        type = lib.types.str;
        default = "sonarr_log";
        description = "Log database name for Sonarr";
      };
    };

    radarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create databases for Radarr";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "radarr";
        description = "PostgreSQL user for Radarr";
      };

      mainDb = lib.mkOption {
        type = lib.types.str;
        default = "radarr_main";
        description = "Main database name for Radarr";
      };

      logDb = lib.mkOption {
        type = lib.types.str;
        default = "radarr_log";
        description = "Log database name for Radarr";
      };
    };

    prowlarr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create databases for Prowlarr";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "prowlarr";
        description = "PostgreSQL user for Prowlarr";
      };

      mainDb = lib.mkOption {
        type = lib.types.str;
        default = "prowlarr_main";
        description = "Main database name for Prowlarr";
      };

      logDb = lib.mkOption {
        type = lib.types.str;
        default = "prowlarr_log";
        description = "Log database name for Prowlarr";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable PostgreSQL
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_15;
      inherit (cfg) dataDir;

      # Listen on localhost only for security
      enableTCPIP = true;
      settings = {
        listen_addresses = lib.mkDefault "127.0.0.1";
        inherit (cfg) port;

        # Performance tuning for media server workload
        shared_buffers = "256MB";
        effective_cache_size = "512MB";
        maintenance_work_mem = "64MB";
        checkpoint_completion_target = 0.9;
        wal_buffers = "16MB";
        default_statistics_target = 100;
        random_page_cost = 1.1;
        effective_io_concurrency = 200;
        work_mem = "16MB";
        min_wal_size = "1GB";
        max_wal_size = "4GB";
      };

      # Authentication configuration
      authentication = lib.mkForce ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   all             postgres                                peer
        local   all             all                                     peer
        host    all             all             127.0.0.1/32            scram-sha-256
        host    all             all             ::1/128                 scram-sha-256
      '';

      # Create users and databases
      ensureDatabases =
        (lib.optionals cfg.sonarr.enable [ cfg.sonarr.mainDb cfg.sonarr.logDb ])
        ++ (lib.optionals cfg.radarr.enable [ cfg.radarr.mainDb cfg.radarr.logDb ])
        ++ (lib.optionals cfg.prowlarr.enable [ cfg.prowlarr.mainDb cfg.prowlarr.logDb ]);

      ensureUsers =
        (lib.optionals cfg.sonarr.enable [{
          name = cfg.sonarr.user;
        }])
        ++ (lib.optionals cfg.radarr.enable [{
          name = cfg.radarr.user;
        }])
        ++ (lib.optionals cfg.prowlarr.enable [{
          name = cfg.prowlarr.user;
        }]);
    };

    # Service to set up database passwords and ownership
    systemd.services.media-postgres-setup = lib.mkIf (cfg.passwordFile != null) {
      description = "Set up PostgreSQL passwords for media services";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
        Group = "postgres";
      };

      script = let
        psql = "${config.services.postgresql.package}/bin/psql";
      in ''
        set -euo pipefail

        PASSWORD=$(cat ${cfg.passwordFile})

        # Set passwords for each enabled service user
        ${lib.optionalString cfg.sonarr.enable ''
          ${psql} -c "ALTER USER ${cfg.sonarr.user} WITH PASSWORD '$PASSWORD';"
          ${psql} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.sonarr.mainDb} TO ${cfg.sonarr.user};"
          ${psql} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.sonarr.logDb} TO ${cfg.sonarr.user};"
        ''}

        ${lib.optionalString cfg.radarr.enable ''
          ${psql} -c "ALTER USER ${cfg.radarr.user} WITH PASSWORD '$PASSWORD';"
          ${psql} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.radarr.mainDb} TO ${cfg.radarr.user};"
          ${psql} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.radarr.logDb} TO ${cfg.radarr.user};"
        ''}

        ${lib.optionalString cfg.prowlarr.enable ''
          ${psql} -c "ALTER USER ${cfg.prowlarr.user} WITH PASSWORD '$PASSWORD';"
          ${psql} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.prowlarr.mainDb} TO ${cfg.prowlarr.user};"
          ${psql} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.prowlarr.logDb} TO ${cfg.prowlarr.user};"
        ''}

        echo "PostgreSQL media database setup complete"
      '';
    };

    # Open firewall only if needed (default: localhost only, no firewall needed)
    # networking.firewall.allowedTCPPorts = lib.mkIf (cfg.host != "localhost" && cfg.host != "127.0.0.1") [
    #   cfg.port
    # ];
  };
}
