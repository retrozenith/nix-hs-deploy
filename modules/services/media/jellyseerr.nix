# Jellyseerr - Media request management for Jellyfin
# https://github.com/Fallenbagel/jellyseerr
#
# Allows users to request movies and TV shows
# Integrates with Sonarr, Radarr, and Jellyfin

{ config, pkgs, lib, ... }:

{
  options.services.jellyseerrServer = {
    enable = lib.mkEnableOption "Jellyseerr request manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5055;
      description = "Port for Jellyseerr web interface";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/jellyseerr";
      description = "Directory for Jellyseerr configuration and database";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall port for Jellyseerr";
    };
  };

  config = lib.mkIf config.services.jellyseerrServer.enable {
    # Use the built-in NixOS Jellyseerr service
    services.jellyseerr = {
      enable = true;
      inherit (config.services.jellyseerrServer) port openFirewall;
    };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${config.services.jellyseerrServer.dataDir} 0750 jellyseerr jellyseerr -"
    ];

    # Firewall configuration
    networking.firewall.allowedTCPPorts = lib.mkIf config.services.jellyseerrServer.openFirewall [
      config.services.jellyseerrServer.port
    ];
  };
}
