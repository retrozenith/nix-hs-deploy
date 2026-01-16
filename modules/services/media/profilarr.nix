# Profilarr - Automated profile synchronization for Sonarr and Radarr
# https://github.com/Santiag0SaysHey/Profilarr
#
# Syncs quality profiles, custom formats, and more between *arr instances

{ config, pkgs, lib, ... }:

let
  cfg = config.services.profilarrServer;
in
{
  options.services.profilarrServer = {
    enable = lib.mkEnableOption "Profilarr profile synchronizer";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6868;
      description = "Port for Profilarr web interface";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/profilarr";
      description = "Directory for Profilarr configuration";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port for Profilarr";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "profilarr";
      description = "User to run Profilarr as";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 851; # Unique UID for profilarr
      description = "UID for profilarr user";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create profilarr user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = "media";
      uid = cfg.uid;
    };

    users.groups.${cfg.user} = {
      gid = cfg.uid;
    };

    # Create config directory
    systemd.tmpfiles.rules = [
      "d ${cfg.configDir} 0750 ${cfg.user} media -"
    ];

    # Enable podman
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # Profilarr container
    virtualisation.oci-containers = {
      backend = "podman";
      containers.profilarr = {
        image = "santiagosayshey/profilarr:latest";
        autoStart = true;

        ports = [
          "${toString cfg.port}:6868"
        ];

        volumes = [
          "${cfg.configDir}:/config:rw"
        ];

        environment = {
          TZ = config.time.timeZone;
          PUID = toString cfg.uid;
          PGID = "993"; # media group GID
        };
        
        extraOptions = [
          "--security-opt=no-new-privileges:true"
        ];
      };
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.port
    ];
  };
}
