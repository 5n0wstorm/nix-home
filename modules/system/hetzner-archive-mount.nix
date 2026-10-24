{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.system.hetznerArchiveMount;
  archivePath = "${cfg.mountPoint}/${cfg.archiveSubdir}";

  # Shared by the mount unit and the watchdog (idempotent: mounts only if needed).
  mountScript = pkgs.writeShellScript "hetzner-archive-mount" ''
    export PATH=${lib.makeBinPath [pkgs.cifs-utils pkgs.coreutils pkgs.util-linux]}:$PATH
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
      telegram boosty twitter simpcity \
      torrents/incomplete torrents/complete \
      usenet/incomplete \
      usenet/complete/books usenet/complete/movies usenet/complete/music usenet/complete/tv \
      media/books media/movies media/music media/tv; do
      mkdir -p "${archivePath}/$dir"
    done

    for f in \
      telegram/urls.txt telegram/url-logs.txt \
      boosty/urls.txt \
      twitter/urls.txt twitter/url-logs.txt \
      simpcity/urls.txt simpcity/url-logs.txt simpcity/cookies.txt; do
      touch "${archivePath}/$f"
      chmod 664 "${archivePath}/$f" || true
    done
  '';
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
          # Restarting would restart every Requires= dependent (long gallery-dl
          # runs); the watchdog handles remounts, so never restart on switch.
          restartIfChanged = false;

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Unmount on stop/shutdown (ordered before network-online.target is
            # torn down). Replaces a separate unit RequiredBy=umount.target, which
            # also had Conflicts=shutdown.target and made every `systemctl reboot`
            # fail with "Transaction contains conflicting jobs".
            ExecStop = "-${pkgs.bash}/bin/sh -c '${pkgs.util-linux}/bin/umount ${cfg.mountPoint} || ${pkgs.util-linux}/bin/umount -l ${cfg.mountPoint}'";
          };

          path = [pkgs.cifs-utils pkgs.coreutils pkgs.util-linux];

          script = "${mountScript}";
        };

        # ----------------------------------------------------------------------
        # WATCHDOG - remount when the CIFS session goes stale ("Host is down")
        # ----------------------------------------------------------------------
        # Remounts in place instead of restarting hetzner-archive-mount.service,
        # which would stop every unit in afterMountServices (Requires=).
        hetzner-archive-watchdog = {
          description = "Remount Hetzner Storage Box if the CIFS mount is stale";
          after = ["hetzner-archive-mount.service"];
          # Only while the mount unit is up (not during boot/shutdown).
          requisite = ["hetzner-archive-mount.service"];
          serviceConfig.Type = "oneshot";
          path = [pkgs.coreutils pkgs.util-linux];
          script = ''
            set -uo pipefail
            if timeout 20 stat -t ${archivePath} >/dev/null 2>&1 \
              && timeout 20 ls ${archivePath} >/dev/null 2>&1; then
              exit 0
            fi
            echo "${archivePath} not accessible; remounting ${cfg.mountPoint}"
            umount -f -l ${cfg.mountPoint} 2>/dev/null || true
            ${mountScript}
            if timeout 20 stat -t ${archivePath} >/dev/null 2>&1; then
              echo "remount OK"
            else
              echo "remount failed; will retry on next timer run" >&2
              exit 1
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

    systemd.timers.hetzner-archive-watchdog = {
      description = "Periodically check the Hetzner Storage Box mount";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "2min";
      };
    };
  };
}
