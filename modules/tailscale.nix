{ config, pkgs, lib, ... }:

{
  options.services.tailscaleConfig = {
    enable = lib.mkEnableOption "Tailscale VPN configuration";

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing Tailscale auth key for automatic authentication";
    };

    exitNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise this node as an exit node";
    };

    advertiseRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of routes to advertise (e.g., ['192.168.1.0/24'])";
    };

    acceptRoutes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Accept routes advertised by other nodes";
    };

    hostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Hostname to use on Tailscale network (defaults to system hostname)";
    };

    enableSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Tailscale SSH (allows SSH access via Tailscale)";
    };

    tags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "ACL tags for this device (e.g., ['tag:server'])";
    };

    extraUpFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags to pass to 'tailscale up'";
    };
  };

  config = lib.mkIf config.services.tailscaleConfig.enable {
    # Enable the Tailscale service
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = lib.mkIf (config.services.tailscaleConfig.exitNode || config.services.tailscaleConfig.advertiseRoutes != [ ]) "server";
    };

    # Allow Tailscale traffic through firewall
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };

    # Enable IP forwarding if advertising routes or acting as exit node
    boot.kernel.sysctl = lib.mkIf (config.services.tailscaleConfig.exitNode || config.services.tailscaleConfig.advertiseRoutes != [ ]) {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    # Auto-connect to Tailscale on boot
    systemd.services.tailscale-autoconnect = lib.mkIf (config.services.tailscaleConfig.authKeyFile != null) {
      description = "Automatic connection to Tailscale";
      after = [ "network-pre.target" "tailscale.service" ];
      wants = [ "network-pre.target" "tailscale.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script =
        let
          cfg = config.services.tailscaleConfig;
          upFlags = lib.concatStringsSep " " (
            [ "--reset" ]
            ++ lib.optional cfg.exitNode "--advertise-exit-node"
            ++ lib.optional (cfg.advertiseRoutes != [ ]) "--advertise-routes=${lib.concatStringsSep "," cfg.advertiseRoutes}"
            ++ lib.optional cfg.acceptRoutes "--accept-routes"
            ++ lib.optional (cfg.hostname != null) "--hostname=${cfg.hostname}"
            ++ lib.optional cfg.enableSSH "--ssh"
            ++ lib.optionals (cfg.tags != [ ]) [ "--advertise-tags=${lib.concatStringsSep "," cfg.tags}" ]
            ++ cfg.extraUpFlags
          );
        in
        ''
          # Wait for tailscaled to be ready
          sleep 2

          # Check if already authenticated
          status="$(${pkgs.tailscale}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)"

          if [ "$status" = "Running" ]; then
            echo "Tailscale already running, updating configuration..."
            ${pkgs.tailscale}/bin/tailscale up ${upFlags}
          else
            echo "Authenticating with Tailscale..."
            ${pkgs.tailscale}/bin/tailscale up ${upFlags} --authkey="$(cat ${cfg.authKeyFile})"
          fi
        '';
    };

    # Ensure tailscale CLI is available
    environment.systemPackages = [ pkgs.tailscale ];
  };
}
