# MergerFS storage pool configuration
# Combines multiple drives into a single union filesystem for media storage
#
# MergerFS is ideal for media servers because:
# - No parity overhead (unlike RAID)
# - Drives can be different sizes
# - Easy to add/remove drives
# - Files are stored intact on individual drives (easy recovery)
# - Supports various policies for file placement

{ config, pkgs, lib, ... }:

{
  options.storage.mergerfs = {
    enable = lib.mkEnableOption "MergerFS storage pool";

    poolPath = lib.mkOption {
      type = lib.types.path;
      default = "/srv/storage";
      description = "Mount point for the merged storage pool";
    };

    branches = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/mnt/disk1" "/mnt/disk2" "/mnt/disk3" ];
      description = "List of paths to merge into the pool";
    };

    branchPattern = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/mnt/disk*";
      description = "Glob pattern for branches (alternative to explicit list)";
    };

    policy = {
      create = lib.mkOption {
        type = lib.types.enum [
          "epmfs" # Existing path, most free space
          "mfs"   # Most free space
          "lfs"   # Least free space
          "eplus" # Existing path, least used space
          "rand"  # Random
          "eplfs" # Existing path, least free space
          "ff"    # First found
          "newest"
        ];
        default = "epmfs";
        description = ''
          Policy for creating new files:
          - epmfs: Existing path, most free space (recommended for media)
          - mfs: Most free space
          - lfs: Least free space
          - eplfs: Existing path, least free space
          - rand: Random distribution
        '';
      };

      search = lib.mkOption {
        type = lib.types.enum [ "ff" "newest" "all" ];
        default = "ff";
        description = "Policy for searching files";
      };
    };

    minFreeSpace = lib.mkOption {
      type = lib.types.str;
      default = "50G";
      description = "Minimum free space on a drive before moving to next";
    };

    cacheMode = lib.mkOption {
      type = lib.types.enum [ "off" "partial" "full" "auto-full" ];
      default = "partial";
      description = ''
        Kernel page cache mode:
        - off: No caching
        - partial: Cache only open files
        - full: Cache all files
        - auto-full: Full caching with automatic invalidation
      '';
    };

    moveOnDelete = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Move files to a single branch on delete (for snapraid compatibility)";
    };

    extraOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "dropcacheonclose=true" "async_read=true" ];
      description = "Additional MergerFS mount options";
    };

    # Disk mount configurations
    disks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          device = lib.mkOption {
            type = lib.types.str;
            description = "Device path (e.g., /dev/disk/by-id/...)";
          };
          fsType = lib.mkOption {
            type = lib.types.str;
            default = "ext4";
            description = "Filesystem type";
          };
          mountOptions = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "defaults" "nofail" ];
            description = "Mount options for this disk";
          };
        };
      });
      default = { };
      example = {
        disk1 = {
          device = "/dev/disk/by-id/ata-WDC_WD40EFRX-1";
          fsType = "ext4";
        };
        disk2 = {
          device = "/dev/disk/by-id/ata-WDC_WD40EFRX-2";
          fsType = "ext4";
        };
      };
      description = "Individual disk configurations";
    };
  };

  config = lib.mkIf config.storage.mergerfs.enable {
    # Install mergerfs
    environment.systemPackages = with pkgs; [
      mergerfs
      mergerfs-tools  # Useful utilities for managing mergerfs pools
    ];

    # Create mount points for individual disks
    systemd.tmpfiles.rules =
      let
        cfg = config.storage.mergerfs;
        diskMountPoints = lib.mapAttrsToList (name: _: "d /mnt/${name} 0755 root root -") cfg.disks;
        poolMountPoint = [ "d ${cfg.poolPath} 0775 root root -" ];
      in
        diskMountPoints ++ poolMountPoint;

    # Mount individual disks
    fileSystems = lib.mkMerge [
      # Individual disk mounts
      (lib.mapAttrs' (name: disk:
        lib.nameValuePair "/mnt/${name}" {
          inherit (disk) device fsType;
          options = disk.mountOptions;
        }
      ) config.storage.mergerfs.disks)

      # MergerFS pool mount
      {
        "${config.storage.mergerfs.poolPath}" = {
          device =
            let
              cfg = config.storage.mergerfs;
              diskBranches = lib.mapAttrsToList (name: _: "/mnt/${name}") cfg.disks;
              allBranches = if cfg.branches != [] then cfg.branches else diskBranches;
            in
              if cfg.branchPattern != null
              then cfg.branchPattern
              else lib.concatStringsSep ":" allBranches;
          fsType = "fuse.mergerfs";
          options =
            let
              cfg = config.storage.mergerfs;
            in [
              "defaults"
              "allow_other"
              "use_ino"
              "category.create=${cfg.policy.create}"
              "category.search=${cfg.policy.search}"
              "minfreespace=${cfg.minFreeSpace}"
              "cache.files=${cfg.cacheMode}"
              "fsname=mergerfs"
              "nonempty"
            ]
            ++ lib.optional cfg.moveOnDelete "moveonenospc=true"
            ++ cfg.extraOptions
            ++ [ "nofail" "x-systemd.requires=local-fs.target" ];
          depends = lib.mapAttrsToList (name: _: "/mnt/${name}") config.storage.mergerfs.disks;
        };
      }
    ];

    # Ensure mergerfs mounts after individual disks
    systemd.services."srv-storage.mount" = lib.mkIf (config.storage.mergerfs.disks != { }) {
      after = lib.mapAttrsToList (name: _: "mnt-${name}.mount") config.storage.mergerfs.disks;
      requires = lib.mapAttrsToList (name: _: "mnt-${name}.mount") config.storage.mergerfs.disks;
    };
  };
}
