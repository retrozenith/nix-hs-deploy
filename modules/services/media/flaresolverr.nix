# FlareSolverr - Proxy server to bypass Cloudflare and DDoS-GUARD protection
# https://github.com/FlareSolverr/FlareSolverr
#
# Used by Prowlarr and other *arr apps to bypass Cloudflare challenges

{ config, pkgs, lib, ... }:

let
  cfg = config.services.flaresolverrServer;
in
{
  options.services.flaresolverrServer = {
    enable = lib.mkEnableOption "FlareSolverr proxy server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8191;
      description = "Port for FlareSolverr service";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port for FlareSolverr";
    };
  };

  config = lib.mkIf cfg.enable {
    services.flaresolverr = {
      enable = true;
      inherit (cfg) port;
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.port
    ];
  };
}
