{ config, pkgs, lib, inputs, hostName, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/tailscale.nix
    ../../modules/motd.nix
    ../../modules/storage/mergerfs.nix
    ../../modules/services/networking/caddy.nix
    ../../modules/services/networking/cloudflare-ddns.nix
    ../../modules/services/misc/vaultwarden.nix
    ../../modules/services/media
  ];

  # MergerFS storage pool configuration
  storage.mergerfs = {
    enable = true;
    poolPath = "/srv/storage";

    disks = {
      disk1 = {
        device = "/dev/disk/by-id/ata-WDC_WD5000AADS-00L4B1_WD-WCAUH1494019";
        fsType = "ext4";
      };
      disk2 = {
        device = "/dev/disk/by-id/ata-WDC_WD10EZEX-22MFCA0_WD-WCC6Y3HENFP8";
        fsType = "ext4";
      };
    };

    policy = {
      create = "epmfs";
      search = "ff";
    };

    minFreeSpace = "50G";
    cacheMode = "partial";

    extraOptions = [
      "dropcacheonclose=true"
      "async_read=true"
    ];
  };

  # Consolidate all services configuration
  services = {
    # Dynamic MOTD with system info and service links
    motd = {
      enable = true;
      # External domains shown in MOTD (optional - uncomment and customize)
      # externalDomains = {
      #   Jellyfin = "jf.yourdomain.com";
      #   Vaultwarden = "vault.yourdomain.com";
      #   Jellyseerr = "request.yourdomain.com";
      #   Prowlarr = "prowlarr.yourdomain.com";
      #   Streamystats = "stats.yourdomain.com";
      # };
    };

    # Enable all media services with common configuration
    mediaServices = {
      enable = true;
      mediaGroup = "media";
      baseMediaDir = "/srv/storage/media";
      baseDownloadDir = "/srv/storage/downloads";

      # PostgreSQL backend for Sonarr, Radarr, Prowlarr (optional - better performance)
      # Uncomment to enable centralized PostgreSQL instead of SQLite
      # usePostgres = true;
      # postgresPasswordFile = config.age.secrets.media-postgres-password.path;
    };

    # Jellyfin with hardware acceleration
    jellyfinServer = {
      hardwareAcceleration.enable = true;
      hardwareAcceleration.type = "vaapi";
    };

    # qBittorrent with VPN (Gluetun)
    qbittorrentVpn = {
      enable = true;
      vpnProvider = "nordvpn";
      vpnType = "wireguard";
      serverCountries = "Romania";
      wireguardPrivateKeyFile = config.age.secrets.gluetun-wireguard-key.path;
      webuiPort = 8080;
      peerPort = 6881;
      downloadDir = "/srv/storage/downloads";
    };

    # Streamystats - Jellyfin analytics
    streamystats = {
      enable = true;
      port = 3000;
      sessionSecretFile = config.age.secrets.streamystats-session-secret.path;
      postgres.passwordFile = config.age.secrets.streamystats-postgres-password.path;
    };

    # Caddy reverse proxy for services
    caddyProxy = {
      enable = true;
      emailFile = config.age.secrets.caddy-email.path;

      jellyfin = {
        enable = true;
        domainFile = config.age.secrets.domain-jellyfin.path;
        port = 8096;
      };

      vaultwarden = {
        enable = true;
        domainFile = config.age.secrets.domain-vault.path;
        port = 8222;
        websocketPort = 3012;
      };

      prowlarr = {
        enable = true;
        domainFile = config.age.secrets.domain-prowlarr.path;
        port = 9696;
      };

      jellyseerr = {
        enable = true;
        domainFile = config.age.secrets.domain-request.path;
        port = 5055;
      };

      streamystats = {
        enable = true;
        domainFile = config.age.secrets.domain-streamystats.path;
        port = 3000;
      };

      tailscaleOnly = false;
    };

    # Vaultwarden - Self-hosted password manager
    vaultwardenConfig = {
      enable = true;
      domainFile = config.age.secrets.domain-vault.path;
      port = 8222;
      websocketPort = 3012;
      signupsAllowed = false;
      invitationsAllowed = true;
      adminTokenFile = config.age.secrets.vaultwarden-admin-token.path;
    };

    # Cloudflare DDNS
    cloudflareDdns = {
      enable = true;
      apiTokenFile = config.age.secrets.cloudflare-api-token.path;
      zoneIdFile = config.age.secrets.cloudflare-zone-id.path;
      interval = "5m";
      ipv4.enable = true;
      ipv6.enable = false;

      domains = [
        {
          nameFile = config.age.secrets.domain-jellyfin.path;
          proxied = true;
          type = "A";
          ttl = 1;
        }
        {
          nameFile = config.age.secrets.domain-prowlarr.path;
          proxied = true;
          type = "A";
          ttl = 1;
        }
        {
          nameFile = config.age.secrets.domain-vault.path;
          proxied = true;
          type = "A";
          ttl = 1;
        }
        {
          nameFile = config.age.secrets.domain-request.path;
          proxied = true;
          type = "A";
          ttl = 1;
        }
        {
          nameFile = config.age.secrets.domain-auth.path;
          proxied = true;
          type = "A";
          ttl = 1;
        }
        {
          nameFile = config.age.secrets.domain-streamystats.path;
          proxied = true;
          type = "A";
          ttl = 1;
        }
      ];
    };

    # Tailscale VPN
    tailscaleConfig = {
      enable = true;
      authKeyFile = config.age.secrets.tailscale-auth-key.path;
      hostname = "andromeda";
      enableSSH = true;
      acceptRoutes = true;
      tags = [ "tag:server" "tag:media" ];
    };
  };

  # Boot configuration
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Networking
  networking = {
    inherit hostName;
    networkmanager.enable = true;
    useDHCP = false; # Explicitly disable global DHCP since we use static IP

    interfaces.enp1s0 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "192.168.0.26";
        prefixLength = 24;
      }];
    };
    defaultGateway = "192.168.0.1";
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # Allow cvictor to run sudo without a password for headless deployments
  security.sudo.extraRules = [{
    users = [ "cvictor" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];

  # Time zone
  time.timeZone = "Europe/Bucharest";

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ro_RO.UTF-8";
    LC_IDENTIFICATION = "ro_RO.UTF-8";
    LC_MEASUREMENT = "ro_RO.UTF-8";
    LC_MONETARY = "ro_RO.UTF-8";
    LC_NAME = "ro_RO.UTF-8";
    LC_NUMERIC = "ro_RO.UTF-8";
    LC_PAPER = "ro_RO.UTF-8";
    LC_TELEPHONE = "ro_RO.UTF-8";
    LC_TIME = "ro_RO.UTF-8";
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    git
    wget
    curl
    tmux
    ncdu
    tree
    smartmontools
    hdparm
    intel-gpu-tools
  ];

  # Admin user
  users.users.cvictor = {
    isNormalUser = true;
    description = "Cristea Florian Victor";
    extraGroups = [ "wheel" "networkmanager" "media" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILpgI8QYYV6UspNyqa1PfDd0LafyR8ebKqky56z6YJd3 andromeda-deploy"
    ];
  };

  # Nix configuration
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" "cvictor" ];
    };
  };

  # SMART monitoring
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications = {
      mail.enable = false;
      wall.enable = true;
    };
  };

  system.stateVersion = "25.11";
}
