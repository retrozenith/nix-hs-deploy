# Cloudflare DDNS service module
# Automatically updates Cloudflare DNS records with your public IP address
#
# Requires a Cloudflare API token with Zone:DNS:Edit permissions

{ config, pkgs, lib, ... }:

{
  options.services.cloudflareDdns = {
    enable = lib.mkEnableOption "Cloudflare DDNS updater";

    apiTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing Cloudflare API token";
    };

    zoneIdFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing Cloudflare Zone ID";
    };

    domains = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Domain name to update (e.g., jellyfin.example.com)";
          };

          nameFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Alternative: path to file containing domain name (for secrets)";
          };

          proxied = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to proxy through Cloudflare (orange cloud)";
          };

          type = lib.mkOption {
            type = lib.types.enum [ "A" "AAAA" ];
            default = "A";
            description = "DNS record type (A for IPv4, AAAA for IPv6)";
          };

          ttl = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "TTL in seconds (1 = automatic)";
          };
        };
      });
      default = [ ];
      description = "List of domains to update";
    };

    ipv4 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Update IPv4 (A) records";
      };

      provider = lib.mkOption {
        type = lib.types.str;
        default = "https://ipv4.icanhazip.com";
        description = "URL to fetch public IPv4 address";
      };
    };

    ipv6 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Update IPv6 (AAAA) records";
      };

      provider = lib.mkOption {
        type = lib.types.str;
        default = "https://ipv6.icanhazip.com";
        description = "URL to fetch public IPv6 address";
      };
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "How often to check and update DNS records (systemd time format)";
    };

    onCalendar = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "*:0/15";
      description = "Alternative to interval: systemd OnCalendar schedule";
    };
  };

  config = lib.mkIf config.services.cloudflareDdns.enable {
    # DDNS update script
    systemd.services.cloudflare-ddns = {
      description = "Cloudflare DDNS updater";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [ curl jq ];

      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        StateDirectory = "cloudflare-ddns";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        PrivateDevices = true;
        
        # Load credentials for access to root-owned secrets
        LoadCredential = [
          "api-token:${config.services.cloudflareDdns.apiTokenFile}"
          "zone-id:${config.services.cloudflareDdns.zoneIdFile}"
        ];
      };

      script = let
        cfg = config.services.cloudflareDdns;
      in ''
        set -euo pipefail

        STATE_DIR="/var/lib/cloudflare-ddns"

        # Read API token and Zone ID from credentials
        API_TOKEN=$(cat "$CREDENTIALS_DIRECTORY/api-token")
        ZONE_ID=$(cat "$CREDENTIALS_DIRECTORY/zone-id")

        # Function to get current public IP
        get_public_ip() {
          local ip_version=$1
          local provider=$2
          curl -s --max-time 10 "$provider" | tr -d '\n'
        }

        # Function to get DNS record ID
        get_record_id() {
          local domain=$1
          local record_type=$2

          curl -s --max-time 30 \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$record_type&name=$domain" \
            | jq -r '.result[0].id // empty'
        }

        # Function to get current DNS record IP
        get_record_ip() {
          local domain=$1
          local record_type=$2

          curl -s --max-time 30 \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$record_type&name=$domain" \
            | jq -r '.result[0].content // empty'
        }

        # Function to update DNS record
        update_record() {
          local domain=$1
          local record_type=$2
          local ip=$3
          local proxied=$4
          local ttl=$5
          local record_id=$6

          local proxied_json="false"
          [ "$proxied" = "1" ] && proxied_json="true"

          if [ -n "$record_id" ]; then
            # Update existing record
            echo "Updating $record_type record for $domain to $ip"
            curl -s --max-time 30 \
              -X PUT \
              -H "Authorization: Bearer $API_TOKEN" \
              -H "Content-Type: application/json" \
              --data "{\"type\":\"$record_type\",\"name\":\"$domain\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied_json}" \
              "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
              | jq -r '.success'
          else
            # Create new record
            echo "Creating $record_type record for $domain with IP $ip"
            curl -s --max-time 30 \
              -X POST \
              -H "Authorization: Bearer $API_TOKEN" \
              -H "Content-Type: application/json" \
              --data "{\"type\":\"$record_type\",\"name\":\"$domain\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied_json}" \
              "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
              | jq -r '.success'
          fi
        }

        # Get current public IPs
        ${lib.optionalString cfg.ipv4.enable ''
          CURRENT_IPV4=$(get_public_ip 4 "${cfg.ipv4.provider}")
          if [ -z "$CURRENT_IPV4" ]; then
            echo "Failed to get public IPv4 address"
          else
            echo "Current IPv4: $CURRENT_IPV4"
          fi
        ''}

        ${lib.optionalString cfg.ipv6.enable ''
          CURRENT_IPV6=$(get_public_ip 6 "${cfg.ipv6.provider}")
          if [ -z "$CURRENT_IPV6" ]; then
            echo "Failed to get public IPv6 address"
          else
            echo "Current IPv6: $CURRENT_IPV6"
          fi
        ''}

        # Process each domain
        ${lib.concatMapStringsSep "\n" (domain: ''
          # Get domain name (from file or direct)
          ${if domain.nameFile != null then ''
            DOMAIN_NAME=$(cat ${domain.nameFile})
          '' else ''
            DOMAIN_NAME="${domain.name}"
          ''}

          echo "Processing domain: $DOMAIN_NAME"

          ${lib.optionalString (cfg.ipv4.enable && domain.type == "A") ''
            if [ -n "''${CURRENT_IPV4:-}" ]; then
              RECORD_ID=$(get_record_id "$DOMAIN_NAME" "A")
              RECORD_IP=$(get_record_ip "$DOMAIN_NAME" "A")

              if [ "$RECORD_IP" != "$CURRENT_IPV4" ]; then
                echo "IPv4 changed: $RECORD_IP -> $CURRENT_IPV4"
                update_record "$DOMAIN_NAME" "A" "$CURRENT_IPV4" "${if domain.proxied then "1" else "0"}" "${toString domain.ttl}" "$RECORD_ID"
              else
                echo "IPv4 unchanged for $DOMAIN_NAME"
              fi
            fi
          ''}

          ${lib.optionalString (cfg.ipv6.enable && domain.type == "AAAA") ''
            if [ -n "''${CURRENT_IPV6:-}" ]; then
              RECORD_ID=$(get_record_id "$DOMAIN_NAME" "AAAA")
              RECORD_IP=$(get_record_ip "$DOMAIN_NAME" "AAAA")

              if [ "$RECORD_IP" != "$CURRENT_IPV6" ]; then
                echo "IPv6 changed: $RECORD_IP -> $CURRENT_IPV6"
                update_record "$DOMAIN_NAME" "AAAA" "$CURRENT_IPV6" "${if domain.proxied then "1" else "0"}" "${toString domain.ttl}" "$RECORD_ID"
              else
                echo "IPv6 unchanged for $DOMAIN_NAME"
              fi
            fi
          ''}
        '') cfg.domains}

        echo "DDNS update completed at $(date)"
      '';
    };

    # Timer for periodic updates
    systemd.timers.cloudflare-ddns = {
      description = "Cloudflare DDNS update timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        ${if config.services.cloudflareDdns.onCalendar != null
          then "OnCalendar"
          else "OnUnitActiveSec"} =
            if config.services.cloudflareDdns.onCalendar != null
            then config.services.cloudflareDdns.onCalendar
            else config.services.cloudflareDdns.interval;
        OnBootSec = "1m";
        RandomizedDelaySec = "30s";
        Persistent = true;
      };
    };
  };
}
