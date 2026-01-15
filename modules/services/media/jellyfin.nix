# Jellyfin - Open source media server
# https://jellyfin.org/
#
# Provides streaming for movies, TV shows, music, and more

{ config, pkgs, lib, ... }:

{
  options.services.jellyfinServer = {
    enable = lib.mkEnableOption "Jellyfin media server";

    user = lib.mkOption {
      type = lib.types.str;
      default = "jellyfin";
      description = "User to run Jellyfin as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "jellyfin";
      description = "Group to run Jellyfin as";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "Port for Jellyfin HTTP interface";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 8920;
      description = "Port for Jellyfin HTTPS interface";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/jellyfin";
      description = "Directory for Jellyfin data and configuration";
    };

    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/jellyfin";
      description = "Directory for Jellyfin cache (transcodes, etc.)";
    };

    mediaDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = [ "/srv/media/movies" "/srv/media/tv" "/srv/media/music" ];
      description = "List of media directories to make accessible to Jellyfin";
    };

    hardwareAcceleration = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable hardware acceleration for transcoding";
      };

      type = lib.mkOption {
        type = lib.types.enum [ "vaapi" "qsv" "nvenc" ];
        default = "vaapi";
        description = "Type of hardware acceleration (vaapi for Intel/AMD, qsv for Intel QuickSync, nvenc for NVIDIA)";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for Jellyfin";
    };

    dlna = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable DLNA server";
      };
    };
  };

  config = lib.mkIf config.services.jellyfinServer.enable {
    # Use the built-in NixOS Jellyfin service
    services.jellyfin = {
      enable = true;
      inherit (config.services.jellyfinServer) user group dataDir cacheDir openFirewall;
    };

    # Create user and group if using defaults
    users.users.${config.services.jellyfinServer.user} = lib.mkIf (config.services.jellyfinServer.user == "jellyfin") {
      isSystemUser = true;
      inherit (config.services.jellyfinServer) group;
      extraGroups = lib.optionals config.services.jellyfinServer.hardwareAcceleration.enable [
        "video"
        "render"
      ];
    };

    users.groups.${config.services.jellyfinServer.group} = lib.mkIf (config.services.jellyfinServer.group == "jellyfin") { };

    # Hardware acceleration support
    # Note: hardware.opengl is deprecated in NixOS 24.05+, using hardware.graphics instead
    hardware.graphics = lib.mkIf config.services.jellyfinServer.hardwareAcceleration.enable {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver  # VAAPI for Intel
        vaapiIntel          # Older Intel VAAPI
        vaapiVdpau          # VDPAU backend for VAAPI
        libvdpau-va-gl      # OpenGL backend for VDPAU
      ] ++ lib.optionals (config.services.jellyfinServer.hardwareAcceleration.type == "qsv") [
        intel-compute-runtime
      ];
    };

    # Create media directories with proper permissions
    systemd.tmpfiles.rules =
      let
        inherit (config.services.jellyfinServer) user group;
      in [
        "d ${config.services.jellyfinServer.dataDir} 0750 ${user} ${group} -"
        "d ${config.services.jellyfinServer.cacheDir} 0750 ${user} ${group} -"
      ];

    # Firewall configuration
    networking.firewall = lib.mkIf config.services.jellyfinServer.openFirewall {
      allowedTCPPorts = [
        config.services.jellyfinServer.port
        config.services.jellyfinServer.httpsPort
      ];
      allowedUDPPorts = lib.optionals config.services.jellyfinServer.dlna.enable [
        1900  # DLNA discovery
        7359  # Jellyfin client discovery
      ];
    };
  };
}
