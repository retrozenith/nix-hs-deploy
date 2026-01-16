# Media services module
# Imports all media-related service modules
#
# This provides a convenient way to import all media services at once
# Each service can be enabled/disabled individually

{ config, pkgs, lib, ... }:

{
  imports = [
    ./jellyfin.nix
    ./sonarr.nix
    ./radarr.nix
    ./prowlarr.nix
    ./jellyseerr.nix
    ./qbittorrent-vpn.nix
    ./streamystats.nix
    ./postgres.nix
    ./flaresolverr.nix
    ./profilarr.nix
  ];

  # Common media group for shared file access
  options.services.mediaServices = {
    enable = lib.mkEnableOption "all media services";

    mediaGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Common group for media file access across all services";
    };

    baseMediaDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/media";
      description = "Base directory for all media files";
    };

    baseDownloadDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/storage/downloads";
      description = "Base directory for downloads";
    };

    usePostgres = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use centralized PostgreSQL for Sonarr, Radarr, and Prowlarr";
    };

    postgresPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing the PostgreSQL password for media services";
    };
  };

  config = lib.mkIf config.services.mediaServices.enable {
    # Ensure media group exists
    users.groups.${config.services.mediaServices.mediaGroup} = { };

    # Create base directories
    systemd.tmpfiles.rules = [
      "d ${config.services.mediaServices.baseMediaDir} 0775 root ${config.services.mediaServices.mediaGroup} -"
      "d ${config.services.mediaServices.baseMediaDir}/movies 0775 root ${config.services.mediaServices.mediaGroup} -"
      "d ${config.services.mediaServices.baseMediaDir}/tv 0775 root ${config.services.mediaServices.mediaGroup} -"
      "d ${config.services.mediaServices.baseMediaDir}/music 0775 root ${config.services.mediaServices.mediaGroup} -"
      "d ${config.services.mediaServices.baseMediaDir}/anime 0775 root ${config.services.mediaServices.mediaGroup} -"
      "d ${config.services.mediaServices.baseDownloadDir} 0775 root ${config.services.mediaServices.mediaGroup} -"
      "d ${config.services.mediaServices.baseDownloadDir}/complete 0775 root ${config.services.mediaServices.mediaGroup} -"
      "d ${config.services.mediaServices.baseDownloadDir}/incomplete 0775 root ${config.services.mediaServices.mediaGroup} -"
    ];

    # Enable individual services with sensible defaults
    services = {
      jellyfinServer = {
        enable = lib.mkDefault true;
        group = config.services.mediaServices.mediaGroup;
        mediaDirs = [
          "${config.services.mediaServices.baseMediaDir}/movies"
          "${config.services.mediaServices.baseMediaDir}/tv"
          "${config.services.mediaServices.baseMediaDir}/music"
          "${config.services.mediaServices.baseMediaDir}/anime"
        ];
      };

      sonarrServer = {
        enable = lib.mkDefault true;
        group = config.services.mediaServices.mediaGroup;
        mediaDir = "${config.services.mediaServices.baseMediaDir}/tv";
        downloadDir = config.services.mediaServices.baseDownloadDir;
        postgres.enable = config.services.mediaServices.usePostgres;
      };

      radarrServer = {
        enable = lib.mkDefault true;
        group = config.services.mediaServices.mediaGroup;
        mediaDir = "${config.services.mediaServices.baseMediaDir}/movies";
        downloadDir = config.services.mediaServices.baseDownloadDir;
        postgres.enable = config.services.mediaServices.usePostgres;
      };

      prowlarrServer = {
        enable = lib.mkDefault true;
        postgres.enable = config.services.mediaServices.usePostgres;
      };

      # Centralized PostgreSQL for media services
      mediaPostgres = lib.mkIf config.services.mediaServices.usePostgres {
        enable = true;
        passwordFile = config.services.mediaServices.postgresPasswordFile;
      };

      jellyseerrServer = {
        enable = lib.mkDefault true;
      };

      flaresolverrServer = {
        enable = lib.mkDefault true;
      };

      profilarrServer = {
        enable = lib.mkDefault true;
      };
    };
  };
}
