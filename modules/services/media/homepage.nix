# Homepage Dashboard - A modern, customizable dashboard
# https://gethomepage.dev/
#
# Uses native NixOS module options for configuration
# API keys are injected via environment file from agenix secrets

{ config, pkgs, lib, ... }:

let
  cfg = config.services.homepageDashboard;
in
{
  options.services.homepageDashboard = {
    enable = lib.mkEnableOption "Homepage Dashboard";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port for Homepage (usually behind reverse proxy)";
    };

    # Secret files for service API keys
    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to environment file containing API keys (agenix secret)";
    };

    # Domain hrefs - these are passed directly since we can't read secrets at eval time
    domains = {
      jellyfin = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:8096";
        description = "Jellyfin URL/domain";
      };

      jellyseerr = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:5055";
        description = "Jellyseerr URL/domain";
      };

      prowlarr = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:9696";
        description = "Prowlarr URL/domain";
      };

      vaultwarden = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:8222";
        description = "Vaultwarden URL/domain";
      };

      streamystats = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:3000";
        description = "Streamystats URL/domain";
      };
    };

    # Service ports for widgets
    ports = {
      jellyfin = lib.mkOption { type = lib.types.port; default = 8096; };
      jellyseerr = lib.mkOption { type = lib.types.port; default = 5055; };
      sonarr = lib.mkOption { type = lib.types.port; default = 8989; };
      radarr = lib.mkOption { type = lib.types.port; default = 7878; };
      prowlarr = lib.mkOption { type = lib.types.port; default = 9696; };
      qbittorrent = lib.mkOption { type = lib.types.port; default = 8080; };
    };
  };

  config = lib.mkIf cfg.enable {
    # Use native NixOS homepage-dashboard options
    services.homepage-dashboard = {
      enable = true;

      # Environment file for API keys
      environmentFile = cfg.envFile;

      # Dashboard settings
      settings = {
        title = "Andromeda Dashboard";
        favicon = "https://raw.githubusercontent.com/gethomepage/homepage/main/public/favicon.ico";
        theme = "dark";
        color = "slate";
        headerStyle = "clean";
        layout = {
          Media = {
            style = "row";
            columns = 2;
          };
          Downloads = {
            style = "row";
            columns = 4;
          };
          Infrastructure = {
            style = "row";
            columns = 2;
          };
        };
      };

      # Services configuration
      services = [
        {
          "Media" = [
            {
              "Jellyfin" = {
                icon = "jellyfin.svg";
                href = cfg.domains.jellyfin;
                description = "Media Server";
                widget = {
                  type = "jellyfin";
                  url = "http://localhost:${toString cfg.ports.jellyfin}";
                  key = "{{HOMEPAGE_VAR_JELLYFIN_KEY}}";
                  enableBlocks = true;
                  enableNowPlaying = true;
                };
              };
            }
            {
              "Jellyseerr" = {
                icon = "jellyseerr.svg";
                href = cfg.domains.jellyseerr;
                description = "Request Management";
                widget = {
                  type = "jellyseerr";
                  url = "http://localhost:${toString cfg.ports.jellyseerr}";
                  key = "{{HOMEPAGE_VAR_JELLYSEER_KEY}}";
                };
              };
            }
          ];
        }
        {
          "Downloads" = [
            {
              "Sonarr" = {
                icon = "sonarr.svg";
                href = "http://localhost:${toString cfg.ports.sonarr}";
                description = "TV Shows";
                widget = {
                  type = "sonarr";
                  url = "http://localhost:${toString cfg.ports.sonarr}";
                  key = "{{HOMEPAGE_VAR_SONARR_KEY}}";
                };
              };
            }
            {
              "Radarr" = {
                icon = "radarr.svg";
                href = "http://localhost:${toString cfg.ports.radarr}";
                description = "Movies";
                widget = {
                  type = "radarr";
                  url = "http://localhost:${toString cfg.ports.radarr}";
                  key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
                };
              };
            }
            {
              "Prowlarr" = {
                icon = "prowlarr.svg";
                href = cfg.domains.prowlarr;
                description = "Indexer Manager";
                widget = {
                  type = "prowlarr";
                  url = "http://localhost:${toString cfg.ports.prowlarr}";
                  key = "{{HOMEPAGE_VAR_PROWLARR_KEY}}";
                };
              };
            }
            {
              "qBittorrent" = {
                icon = "qbittorrent.svg";
                href = "http://192.168.0.26:${toString cfg.ports.qbittorrent}";
                description = "Torrent Client";
                widget = {
                  type = "qbittorrent";
                  url = "http://192.168.0.26:${toString cfg.ports.qbittorrent}";
                  username = "{{HOMEPAGE_VAR_QBITTORRENT_USERNAME}}";
                  password = "{{HOMEPAGE_VAR_QBITTORRENT_PASSWORD}}";
                };
              };
            }
          ];
        }
        {
          "Infrastructure" = [
            {
              "Vaultwarden" = {
                icon = "vaultwarden.svg";
                href = cfg.domains.vaultwarden;
                description = "Password Manager";
              };
            }
            {
              "Streamystats" = {
                icon = "mdi-chart-bar";
                href = cfg.domains.streamystats;
                description = "Jellyfin Analytics";
              };
            }
          ];
        }
      ];

      # Widgets for system info
      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/";
          };
        }
        {
          datetime = {
            format = {
              dateStyle = "long";
              timeStyle = "short";
            };
          };
        }
      ];

      # Bookmarks
      bookmarks = [
        {
          "Quick Links" = [
            {
              "GitHub" = [
                {
                  icon = "github.svg";
                  href = "https://github.com";
                }
              ];
            }
            {
              "NixOS Wiki" = [
                {
                  icon = "nixos.svg";
                  href = "https://wiki.nixos.org";
                }
              ];
            }
          ];
        }
      ];
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 8082 ];
  };
}
