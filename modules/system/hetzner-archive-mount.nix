{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.system.hetznerArchiveMount;
  archivePath = "${cfg.mountPoint}/${cfg.archiveSubdir}";
in {
  options.fleet.system.hetznerArchiveMount = {
    enable = mkEnableOption "Persistent CIFS mount of the Hetzner Storage Box archive tree";

    mountPoint = mkOption {
      type = types.str;
      default = "/mnt/hetzner";
      description = "Local mount point for the Hetzner SMB share root.";
    };

    archiveSubdir = mkOption {
      type = types.str;
      default = "archive";
      description = "Subdirectory on the share used for downloader and gallery-dl data.";
    };

    archivePath = mkOption {
      type = types.str;
      default = archivePath;
      readOnly = true;
      description = "Full path to the archive directory on the mounted share.";
    };

    smbShareFile = mkOption {
      type = types.path;
      default = "/run/secrets/hetzner_smb/share";
    };

    smbUsernameFile = mkOption {
      type = types.path;
      default = "/run/secrets/hetzner_smb/username";
    };

    smbPasswordFile = mkOption {
      type = types.path;
      default = "/run/secrets/hetzner_smb/password";
    };

    smbMountOptions = mkOption {
      type = types.str;
      default = "vers=3.0,uid=0,gid=1500,dir_mode=02775,file_mode=0664,nofail";
      description = "Extra mount.cifs -o options (username/password appended at runtime). gid=1500 matches fleet.media.shared.";
    };

    afterMountServices = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "systemd units that must start only after the archive mount is up.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.cifs-utils];

    systemd.tmpfiles.rules = [
      "d ${cfg.mountPoint} 0755 root root -"
    ];

    systemd.services = mkMerge [
      {
        hetzner-archive-mount = {
          description = "Mount Hetzner Storage Box and ensure archive directory exists";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target" "sops-nix.service"];
          wants = ["network-online.target"];
          before = cfg.afterMountServices;

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          path = [pkgs.cifs-utils pkgs.coreutils pkgs.util-linux];

          script = ''
            set -euo pipefail
            SHARE=$(tr -d '\n\r' < ${cfg.smbShareFile})
            USER=$(tr -d '\n\r' < ${cfg.smbUsernameFile})
            PASS=$(tr -d '\n\r' < ${cfg.smbPasswordFile})

            mkdir -p ${cfg.mountPoint}

            if ! ${pkgs.util-linux}/bin/mountpoint -q ${cfg.mountPoint}; then
              mount.cifs "$SHARE" ${cfg.mountPoint} \
                -o "${cfg.smbMountOptions},username=$USER,password=$PASS"
            fi

            mkdir -p ${archivePath}
            chmod 2775 ${archivePath}

            # Downloader + gallery-dl layout (CIFS — created after mount, not via tmpfiles)
            for dir in \
              telegram boosty twitter \
              torrents/incomplete torrents/complete \
              usenet/incomplete \
              usenet/complete/books usenet/complete/movies usenet/complete/music usenet/complete/tv \
              media/books media/movies media/music media/tv; do
              mkdir -p "${archivePath}/$dir"
            done

            for f in \
              telegram/urls.txt telegram/url-logs.txt \
              boosty/urls.txt \
              twitter/urls.txt twitter/url-logs.txt; do
              touch "${archivePath}/$f"
              chmod 664 "${archivePath}/$f" || true
            done
          '';
        };

        hetzner-archive-mount-pre-stop = {
          description = "Unmount Hetzner Storage Box on shutdown";
          requiredBy = ["umount.target"];
          before = ["umount.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [pkgs.util-linux];
          script = ''
            if ${pkgs.util-linux}/bin/mountpoint -q ${cfg.mountPoint}; then
              umount ${cfg.mountPoint} || true
            fi
          '';
        };
      }
      (foldl' (
        acc: svc:
          acc
          // {
            ${svc} = {
              after = mkAfter ["hetzner-archive-mount.service"];
              requires = mkAfter ["hetzner-archive-mount.service"];
            };
          }
      ) {}
      cfg.afterMountServices)
    ];
  };
}
