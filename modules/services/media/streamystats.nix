# Streamystats - Jellyfin statistics and analytics
# Providing analytics and data visualization
#
# https://github.com/fredrikburmester/streamystats

{ config, pkgs, lib, ... }:

{
  options.services.streamystats = {
    enable = lib.mkEnableOption "Streamystats for Jellyfin analytics";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for Streamystats web interface";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/streamystats";
      description = "Directory for Streamystats data (PostgreSQL)";
    };

    sessionSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing session secret";
    };

    postgres = {
      user = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
        description = "PostgreSQL username";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing PostgreSQL password";
      };

      database = lib.mkOption {
        type = lib.types.str;
        default = "streamystats";
        description = "PostgreSQL database name";
      };
    };

    cron = {
      activitySync = lib.mkOption {
        type = lib.types.str;
        default = "*/1 * * * *";
        description = "Cron schedule for activity sync";
      };

      recentItemsSync = lib.mkOption {
        type = lib.types.str;
        default = "*/1 * * * *";
        description = "Cron schedule for recent items sync";
      };

      userSync = lib.mkOption {
        type = lib.types.str;
        default = "*/1 * * * *";
        description = "Cron schedule for user sync";
      };

      peopleSync = lib.mkOption {
        type = lib.types.str;
        default = "*/15 * * * *";
        description = "Cron schedule for people sync";
      };

      embeddingsSync = lib.mkOption {
        type = lib.types.str;
        default = "*/15 * * * *";
        description = "Cron schedule for embeddings sync";
      };

      geolocationSync = lib.mkOption {
        type = lib.types.str;
        default = "*/5 * * * *";
        description = "Cron schedule for geolocation sync";
      };

      fingerprintSync = lib.mkOption {
        type = lib.types.str;
        default = "0 4 * * *";
        description = "Cron schedule for fingerprint sync";
      };

      jobCleanup = lib.mkOption {
        type = lib.types.str;
        default = "*/1 * * * *";
        description = "Cron schedule for job cleanup";
      };

      oldJobCleanup = lib.mkOption {
        type = lib.types.str;
        default = "0 3 * * *";
        description = "Cron schedule for old job cleanup";
      };

      fullSync = lib.mkOption {
        type = lib.types.str;
        default = "0 2 * * *";
        description = "Cron schedule for full sync";
      };

      deletedItemsCleanup = lib.mkOption {
        type = lib.types.str;
        default = "0 * * * *";
        description = "Cron schedule for deleted items cleanup";
      };
    };

    skipStartupFullSync = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip full sync on startup";
    };

    sessionPollInterval = lib.mkOption {
      type = lib.types.int;
      default = 5000;
      description = "Session poll interval in milliseconds";
    };
  };

  config = lib.mkIf config.services.streamystats.enable {
    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${config.services.streamystats.dataDir} 0750 root root -"
      "d ${config.services.streamystats.dataDir}/postgres 0750 root root -"
    ];

    # Streamystats container using podman
    virtualisation.oci-containers = {
      backend = "podman";

      containers.streamystats = {
        image = "docker.io/fredrikburmester/streamystats-v2-aio:latest";
        autoStart = true;

        extraOptions = [
          "--security-opt=no-new-privileges:true"
        ];

        ports = [
          "${toString config.services.streamystats.port}:3000"
        ];

        volumes = [
          "${config.services.streamystats.dataDir}/postgres:/var/lib/postgresql/data:rw"
        ];

        environment = {
          POSTGRES_USER = config.services.streamystats.postgres.user;
          POSTGRES_DB = config.services.streamystats.postgres.database;
          NODE_ENV = "production";
          TZ = config.time.timeZone;

          # Cron schedules
          SESSION_POLL_INTERVAL_MS = toString config.services.streamystats.sessionPollInterval;
          CRON_ACTIVITY_SYNC = config.services.streamystats.cron.activitySync;
          CRON_RECENT_ITEMS_SYNC = config.services.streamystats.cron.recentItemsSync;
          CRON_USER_SYNC = config.services.streamystats.cron.userSync;
          CRON_PEOPLE_SYNC = config.services.streamystats.cron.peopleSync;
          CRON_EMBEDDINGS_SYNC = config.services.streamystats.cron.embeddingsSync;
          CRON_GEOLOCATION_SYNC = config.services.streamystats.cron.geolocationSync;
          CRON_FINGERPRINT_SYNC = config.services.streamystats.cron.fingerprintSync;
          CRON_JOB_CLEANUP = config.services.streamystats.cron.jobCleanup;
          CRON_OLD_JOB_CLEANUP = config.services.streamystats.cron.oldJobCleanup;
          CRON_FULL_SYNC = config.services.streamystats.cron.fullSync;
          CRON_DELETED_ITEMS_CLEANUP = config.services.streamystats.cron.deletedItemsCleanup;
          SKIP_STARTUP_FULL_SYNC = if config.services.streamystats.skipStartupFullSync then "true" else "false";
        };

        environmentFiles = lib.mkIf (
          config.services.streamystats.sessionSecretFile != null ||
          config.services.streamystats.postgres.passwordFile != null
        ) [
          "/run/streamystats/env"
        ];
      };
    };

    # Service to generate environment file from secrets
    systemd.services.streamystats-env-generator = lib.mkIf (
      config.services.streamystats.sessionSecretFile != null ||
      config.services.streamystats.postgres.passwordFile != null
    ) {
      description = "Generate Streamystats environment from secrets";
      before = [ "podman-streamystats.service" ];
      requiredBy = [ "podman-streamystats.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
      };

      script = let
        cfg = config.services.streamystats;
      in ''
        set -euo pipefail
        mkdir -p /run/streamystats

        ${lib.optionalString (cfg.postgres.passwordFile != null) ''
        POSTGRES_PASSWORD=$(cat ${cfg.postgres.passwordFile})
        ''}
        ${lib.optionalString (cfg.sessionSecretFile != null) ''
        SESSION_SECRET=$(cat ${cfg.sessionSecretFile})
        ''}

        cat > /run/streamystats/env << ENDOFFILE
        ${lib.optionalString (cfg.postgres.passwordFile != null) ''
        POSTGRES_PASSWORD=$POSTGRES_PASSWORD
        DATABASE_URL=postgresql://${cfg.postgres.user}:$POSTGRES_PASSWORD@127.0.0.1:5432/${cfg.postgres.database}
        ''}
        ${lib.optionalString (cfg.sessionSecretFile != null) ''
        SESSION_SECRET=$SESSION_SECRET
        ''}
        ENDOFFILE

        chmod 400 /run/streamystats/env
      '';
    };

    # Enable podman if not already enabled
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    # Firewall rules
    networking.firewall.allowedTCPPorts = [
      config.services.streamystats.port
    ];
  };
}
