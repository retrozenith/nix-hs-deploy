# Dynamic MOTD (Message of the Day) module
# Displays system information, IP addresses, and service access links on SSH login
#
# Features:
# - System information (hostname, kernel, uptime, load)
# - Network information (IP addresses)
# - Storage usage
# - Service status and access URLs
# - Tailscale status (if enabled)

{ config, pkgs, lib, ... }:

let
  cfg = config.services.motd;

  # Generate the MOTD script
  motdScript = pkgs.writeShellScript "dynamic-motd" ''
    #!/usr/bin/env bash

    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m' # No Color

    # Get system info
    HOSTNAME=$(hostname)
    KERNEL=$(uname -r)
    UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
    LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    MEMORY=$(free -h | awk '/^Mem:/ {printf "%s / %s (%.1f%%)", $3, $2, $3/$2*100}')

    # Get CPU info
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //' || echo "Unknown")
    CPU_CORES=$(nproc 2>/dev/null || echo "?")

    # Get IP addresses
    LOCAL_IP=$(ip -4 addr show scope global 2>/dev/null | grep inet | head -1 | awk '{print $2}' | cut -d/ -f1 || echo "N/A")
    ALL_IPS=$(ip -4 addr show scope global 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | tr '\n' ' ' || echo "N/A")

    # Get Tailscale IP if available
    TAILSCALE_IP=""
    TAILSCALE_STATUS=""
    if command -v tailscale &> /dev/null; then
      TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
      TAILSCALE_STATUS=$(tailscale status --self 2>/dev/null | head -1 || echo "")
    fi

    # Service status helper
    service_status() {
      local service="$1"
      if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "''${GREEN}●''${NC}"
      elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        echo -e "''${YELLOW}○''${NC}"
      else
        echo -e "''${RED}○''${NC}"
      fi
    }

    # Container status helper (for podman)
    container_status() {
      local container="$1"
      if podman ps --format "{{.Names}}" 2>/dev/null | grep -q "^''${container}$"; then
        echo -e "''${GREEN}●''${NC}"
      else
        echo -e "''${RED}○''${NC}"
      fi
    }

    # Print header
    echo ""
    echo -e "''${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
    echo -e "''${BOLD}''${CYAN}  🌌 Welcome to ''${HOSTNAME}''${NC}"
    echo -e "''${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
    echo ""

    # System Information
    echo -e "''${BOLD}''${BLUE}📊 System Information''${NC}"
    echo -e "   ''${DIM}Kernel:''${NC}    $KERNEL"
    echo -e "   ''${DIM}CPU:''${NC}       $CPU_MODEL ($CPU_CORES cores)"
    echo -e "   ''${DIM}Memory:''${NC}    $MEMORY"
    echo -e "   ''${DIM}Load:''${NC}      $LOAD"
    echo -e "   ''${DIM}Uptime:''${NC}    $UPTIME"
    echo ""

    # Network Information
    echo -e "''${BOLD}''${BLUE}🌐 Network''${NC}"
    echo -e "   ''${DIM}Local IP:''${NC}  $LOCAL_IP"
    if [ -n "$TAILSCALE_IP" ]; then
      echo -e "   ''${DIM}Tailscale:''${NC} $TAILSCALE_IP"
    fi
    echo ""

    ${lib.optionalString cfg.showStorage ''
    # Storage
    echo -e "''${BOLD}''${BLUE}💾 Storage''${NC}"
    df -h / /srv/storage 2>/dev/null | tail -n +2 | while read -r line; do
      MOUNT=$(echo "$line" | awk '{print $6}')
      USED=$(echo "$line" | awk '{print $3}')
      TOTAL=$(echo "$line" | awk '{print $2}')
      PERCENT=$(echo "$line" | awk '{print $5}')
      echo -e "   ''${DIM}$MOUNT:''${NC} $USED / $TOTAL ($PERCENT)"
    done
    echo ""
    ''}

    ${lib.optionalString cfg.showServices ''
    # Services Status
    echo -e "''${BOLD}''${BLUE}🔧 Services''${NC}"

    # Media Services
    printf "   $(service_status jellyfin) %-12s" "Jellyfin"
    printf "   $(service_status sonarr) %-12s" "Sonarr"
    printf "   $(service_status radarr) %-12s\n" "Radarr"
    printf "   $(service_status prowlarr) %-12s" "Prowlarr"
    printf "   $(service_status jellyseerr) %-12s" "Jellyseerr"
    printf "   $(container_status qbittorrent) %-12s\n" "qBittorrent"

    # Other services
    printf "   $(service_status caddy) %-12s" "Caddy"
    printf "   $(service_status vaultwarden) %-12s" "Vaultwarden"
    printf "   $(container_status streamystats) %-12s\n" "Streamystats"

    # VPN status
    if podman ps --format "{{.Names}}" 2>/dev/null | grep -q "^gluetun$"; then
      VPN_IP=$(podman exec gluetun wget -qO- ifconfig.me 2>/dev/null || echo "checking...")
      echo -e "   $(container_status gluetun) Gluetun VPN   ''${DIM}(Public IP: $VPN_IP)''${NC}"
    fi
    echo ""
    ''}

    ${lib.optionalString cfg.showNetworkLinks ''
    # Service Access Links
    echo -e "''${BOLD}''${BLUE}🔗 Access Links''${NC}"
    echo ""
    echo -e "   ''${BOLD}Local Network:''${NC}"
    echo -e "   ''${DIM}├─''${NC} Jellyfin     http://$LOCAL_IP:8096"
    echo -e "   ''${DIM}├─''${NC} Sonarr       http://$LOCAL_IP:8989"
    echo -e "   ''${DIM}├─''${NC} Radarr       http://$LOCAL_IP:7878"
    echo -e "   ''${DIM}├─''${NC} Prowlarr     http://$LOCAL_IP:9696"
    echo -e "   ''${DIM}├─''${NC} Jellyseerr   http://$LOCAL_IP:5055"
    echo -e "   ''${DIM}├─''${NC} qBittorrent  http://$LOCAL_IP:8080"
    echo -e "   ''${DIM}├─''${NC} Streamystats http://$LOCAL_IP:3000"
    echo -e "   ''${DIM}└─''${NC} Vaultwarden  http://$LOCAL_IP:8222"

    if [ -n "$TAILSCALE_IP" ]; then
      echo ""
      echo -e "   ''${BOLD}Tailscale:''${NC}"
      echo -e "   ''${DIM}├─''${NC} Jellyfin     http://$TAILSCALE_IP:8096"
      echo -e "   ''${DIM}├─''${NC} Sonarr       http://$TAILSCALE_IP:8989"
      echo -e "   ''${DIM}├─''${NC} Radarr       http://$TAILSCALE_IP:7878"
      echo -e "   ''${DIM}├─''${NC} Prowlarr     http://$TAILSCALE_IP:9696"
      echo -e "   ''${DIM}├─''${NC} Jellyseerr   http://$TAILSCALE_IP:5055"
      echo -e "   ''${DIM}├─''${NC} qBittorrent  http://$TAILSCALE_IP:8080"
      echo -e "   ''${DIM}├─''${NC} Streamystats http://$TAILSCALE_IP:3000"
      echo -e "   ''${DIM}└─''${NC} Vaultwarden  http://$TAILSCALE_IP:8222"
    fi

    ${lib.optionalString (cfg.externalDomains != {}) ''
    echo ""
    echo -e "   ''${BOLD}External (HTTPS):''${NC}"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: domain: ''
    echo -e "   ''${DIM}├─''${NC} ${name}  https://${domain}"
    '') cfg.externalDomains)}
    ''}
    ''}

    ${lib.optionalString (cfg.extraInfo != "") ''
    echo ""
    echo -e "''${BOLD}''${BLUE}📝 Additional Information''${NC}"
    echo -e "${cfg.extraInfo}"
    ''}

    echo ""
    echo -e "''${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
    echo -e "''${DIM}  Last login info above | $(date '+%Y-%m-%d %H:%M:%S')''${NC}"
    echo ""
  '';

in
{
  options.services.motd = {
    enable = lib.mkEnableOption "dynamic MOTD with system info and service links";

    externalDomains = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {
        Jellyfin = "jf.example.com";
        Vaultwarden = "vault.example.com";
      };
      description = "External domain names to display in the MOTD";
    };

    showStorage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show storage usage information";
    };

    showServices = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show service status";
    };

    showNetworkLinks = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show network access links";
    };

    extraInfo = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra information to display at the end of the MOTD";
    };
  };

  config = lib.mkIf cfg.enable {
    # Disable the default NixOS MOTD
    users.motd = null;

    # Create the dynamic MOTD script
    environment.etc."profile.d/motd.sh" = {
      text = ''
        # Only show MOTD for interactive shells
        if [[ $- == *i* ]] && [[ -z "$MOTD_SHOWN" ]]; then
          export MOTD_SHOWN=1
          ${motdScript}
        fi
      '';
      mode = "0755";
    };

    # Also show on SSH login
    programs.bash.interactiveShellInit = lib.mkAfter ''
      if [[ -z "$MOTD_SHOWN" ]] && [[ -n "$SSH_CONNECTION" ]]; then
        export MOTD_SHOWN=1
        ${motdScript}
      fi
    '';

    # Ensure required tools are available
    environment.systemPackages = with pkgs; [
      iproute2
      procps
      coreutils
    ];
  };
}
