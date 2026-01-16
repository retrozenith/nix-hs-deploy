# qBittorrent with VPN (Gluetun) container module
# Routes qBittorrent traffic through VPN using WireGuard
#
# Gluetun creates a VPN tunnel and qBittorrent runs inside its network namespace
# All qBittorrent traffic is routed through the VPN - no leaks possible

{ config, pkgs, lib, ... }:

{
  options.services.qbittorrentVpn = {
    enable = lib.mkEnableOption "qBittorrent with VPN (via Gluetun)";

    vpnProvider = lib.mkOption {
      type = lib.types.str;
      default = "nordvpn";
      description = "VPN service provider";
    };

    vpnType = lib.mkOption {
      type = lib.types.enum [ "wireguard" "openvpn" ];
      default = "wireguard";
      description = "VPN connection type";
    };

    serverCountries = lib.mkOption {
      type = lib.types.str;
      default = "Romania";
      description = "VPN server countries";
    };

    wireguardPrivateKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing WireGuard private key";
    };

    webuiPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "qBittorrent WebUI port";
    };

    peerPort = lib.mkOption {
      type = lib.types.port;
      default = 6881;
      description = "BitTorrent peer port";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/qbittorrent";
      description = "qBittorrent configuration directory";
    };

    downloadDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/storage/downloads";
      description = "Download directory for torrents";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/gluetun";
      description = "Directory for Gluetun/VPN data";
    };

    dns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "DNS servers to use inside VPN";
    };
  };

  config = lib.mkIf config.services.qbittorrentVpn.enable {
    # Create qbittorrent user and group for proper permissions
    users.users.qbittorrent = {
      isSystemUser = true;
      group = "qbittorrent";
      uid = 850; # Fixed UID for container compatibility
    };

    users.groups.qbittorrent = {
      gid = 850; # Fixed GID for container compatibility
    };

    # Create data directories with proper permissions
    systemd.tmpfiles.rules = [
      "d ${config.services.qbittorrentVpn.dataDir} 0750 root root -"
      "d ${config.services.qbittorrentVpn.configDir} 0750 qbittorrent qbittorrent -"
      "d ${config.services.qbittorrentVpn.downloadDir} 0775 qbittorrent qbittorrent -"
    ];

    # Enable podman for containers
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    # Gluetun + qBittorrent containers
    virtualisation.oci-containers = {
      backend = "podman";

      containers.gluetun = {
        image = "qmcgaw/gluetun:latest";
        autoStart = true;

        extraOptions = [
          "--cap-add=NET_ADMIN"
          "--device=/dev/net/tun"
          "--security-opt=no-new-privileges:true"
        ];

        # Ports are exposed through Gluetun (qBittorrent uses Gluetun's network)
        ports = [
          "${toString config.services.qbittorrentVpn.webuiPort}:8080"
          "${toString config.services.qbittorrentVpn.peerPort}:6881"
          "${toString config.services.qbittorrentVpn.peerPort}:6881/udp"
        ];

        volumes = [
          "${config.services.qbittorrentVpn.dataDir}:/gluetun:rw"
        ];

        environment = {
          VPN_SERVICE_PROVIDER = config.services.qbittorrentVpn.vpnProvider;
          VPN_TYPE = config.services.qbittorrentVpn.vpnType;
          SERVER_COUNTRIES = config.services.qbittorrentVpn.serverCountries;
          TZ = config.time.timeZone;
          FIREWALL_VPN_INPUT_PORTS = toString config.services.qbittorrentVpn.peerPort;
          DOT = "off";
          DNS_ADDRESS = builtins.head config.services.qbittorrentVpn.dns;
        };

        environmentFiles = [
          "/run/qbittorrent-vpn/env"
        ];
      };

      # qBittorrent uses Gluetun's network namespace
      containers.qbittorrent = {
        image = "lscr.io/linuxserver/qbittorrent:latest";
        autoStart = true;
        dependsOn = [ "gluetun" ];

        extraOptions = [
          "--network=container:gluetun"
          "--security-opt=no-new-privileges:true"
        ];

        volumes = [
          "${config.services.qbittorrentVpn.configDir}:/config:rw"
          "${config.services.qbittorrentVpn.downloadDir}:/torrents:rw"
        ];

        environment = {
          PUID = "850"; # qbittorrent user UID
          PGID = "850"; # qbittorrent group GID
          TZ = config.time.timeZone;
          WEBUI_PORT = "8080";
          TORRENTING_PORT = toString config.services.qbittorrentVpn.peerPort;
        };
      };
    };

    # Generate environment file with WireGuard key from secret
    systemd.services.qbittorrent-vpn-env-generator = {
      description = "Generate qBittorrent VPN environment from secrets";
      before = [ "podman-gluetun.service" ];
      requiredBy = [ "podman-gluetun.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
      };

      script = ''
        set -euo pipefail
        mkdir -p /run/qbittorrent-vpn

        WIREGUARD_KEY=$(cat ${config.services.qbittorrentVpn.wireguardPrivateKeyFile})

        cat > /run/qbittorrent-vpn/env << EOF
        WIREGUARD_PRIVATE_KEY=$WIREGUARD_KEY
        EOF

        chmod 400 /run/qbittorrent-vpn/env
      '';
    };

    # Firewall rules - only expose qBittorrent ports
    networking.firewall = {
      allowedTCPPorts = [
        config.services.qbittorrentVpn.webuiPort
        config.services.qbittorrentVpn.peerPort
      ];
      allowedUDPPorts = [
        config.services.qbittorrentVpn.peerPort
      ];
    };
  };
}
