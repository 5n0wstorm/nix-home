{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.system.backupVarLib;

  pathsLabel = concatStringsSep ", " cfg.paths;
  resticPathArgs = concatMapStringsSep " " escapeShellArg cfg.paths;
  resticExcludeArgs = concatMapStringsSep " " (ex: "--exclude=${escapeShellArg ex}") cfg.excludes;

  # msmtp does not support `tls_min_version` (it errors with "unknown command").
  # Use gnutls priority strings via `tls_priorities` instead.
  tlsPrioritiesForMinVersion = v:
    if v == ""
    then ""
    else if v == "TLS1.0" || v == "TLSv1.0"
    then "NORMAL:-VERS-ALL:+VERS-TLS1.3:+VERS-TLS1.2:+VERS-TLS1.1:+VERS-TLS1.0"
    else if v == "TLS1.1" || v == "TLSv1.1"
    then "NORMAL:-VERS-ALL:+VERS-TLS1.3:+VERS-TLS1.2:+VERS-TLS1.1"
    else if v == "TLS1.2" || v == "TLSv1.2"
    then "NORMAL:-VERS-ALL:+VERS-TLS1.3:+VERS-TLS1.2"
    else if v == "TLS1.3" || v == "TLSv1.3"
    then "NORMAL:-VERS-ALL:+VERS-TLS1.3"
    else "";

  # Build the backup script
  backupScript = pkgs.writeShellScript "backup-var-lib" ''
        set -euo pipefail

        HOSTNAME="${config.networking.hostName}"
        BACKUP_PATHS="${pathsLabel}"

        # Logging helpers
        log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ''$*"; }
        log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ''$*" >&2; }

        on_failure() {
          log_error "Backup failed"
          send_email "❌ Backup Failed on ''${HOSTNAME}" "Backup job failed at $(date)

    Check logs: journalctl -u backup-var-lib.service

    Hostname: ''${HOSTNAME}
    Paths: ''${BACKUP_PATHS}
    Repository: ${cfg.repoPath}"
          exit 1
        }

        # Email notification helper
        send_email() {
          local subject="''${1}"
          local body="''${2}"

          # Create msmtp config
          cat > /tmp/msmtprc.''$$ <<EOF
        account default
        host ${cfg.email.smtp.host}
        port ${toString cfg.email.smtp.port}
        from ${cfg.email.from}
        auth on
        user $(cat ${cfg.email.smtp.usernameFile})
        password $(cat ${cfg.email.smtp.passwordFile})
        tls on
        tls_starttls on
        tls_certcheck ${
      if cfg.email.smtp.tls.skipVerify
      then "off"
      else "on"
    }
        ${optionalString ((tlsPrioritiesForMinVersion cfg.email.smtp.tls.minimumVersion) != "") "tls_priorities ${tlsPrioritiesForMinVersion cfg.email.smtp.tls.minimumVersion}"}
        logfile /var/log/backup-var-lib-msmtp.log
        EOF
          chmod 600 /tmp/msmtprc.''$$

          # Send email
          echo -e "Subject: ''${subject}\n\n''${body}" | \
            msmtp --file=/tmp/msmtprc.''$$ -t "${cfg.email.to}"

          rm -f /tmp/msmtprc.''$$
        }

        # Trap errors and send failure email
        trap on_failure ERR

        START_TIME=$(date +%s)
        log "Starting backup of ''${BACKUP_PATHS} to ${cfg.repoPath}"

        # Read SMB credentials
        SMB_SHARE=$(cat ${cfg.secrets.smbShareFile})
        SMB_USERNAME=$(cat ${cfg.secrets.smbUsernameFile})
        SMB_PASSWORD=$(cat ${cfg.secrets.smbPasswordFile})

        # Create mount point if it doesn't exist
        mkdir -p ${cfg.mountPoint}

        log "Mounting SMB share..."
        mount.cifs \
          "''${SMB_SHARE}" \
          ${cfg.mountPoint} \
          -o "${cfg.smbMountOptions},username=''${SMB_USERNAME},password=''${SMB_PASSWORD}"

        # Ensure unmount on exit; report failures via on_failure
        trap on_failure ERR
        trap 'log "Unmounting SMB share..."; umount ${cfg.mountPoint} 2>/dev/null || true' EXIT

        # Initialize restic repo if it doesn't exist
        export RESTIC_PASSWORD_FILE=${cfg.secrets.resticPasswordFile}
        export RESTIC_REPOSITORY=${cfg.repoPath}

        if ! restic snapshots &>/dev/null; then
          log "Initializing new restic repository..."
          restic init
        fi

      # Run backup
        log "Running restic backup..."
        BACKUP_OUTPUT=$(restic backup ${resticPathArgs} \
          ${resticExcludeArgs} \
          --one-file-system \
          --verbose 2>&1)

        BACKUP_EXIT=''$?
        if [ ''${BACKUP_EXIT} -ne 0 ]; then
          log_error "Restic backup failed with exit code ''${BACKUP_EXIT}"
          exit ''${BACKUP_EXIT}
        fi

        # Apply retention policy
        log "Applying retention policy..."
        FORGET_OUTPUT=$(restic forget --prune \
          --keep-daily ${toString cfg.retention.keepDaily} \
          --keep-weekly ${toString cfg.retention.keepWeekly} \
          --keep-monthly ${toString cfg.retention.keepMonthly} \
          --verbose 2>&1)

        # Get repository stats
        log "Gathering repository statistics..."
        STATS_OUTPUT=$(restic stats --mode raw-data 2>&1 || echo "Stats unavailable")

        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        DURATION_MIN=$((DURATION / 60))
        DURATION_SEC=$((DURATION % 60))

        # Extract useful info from backup output
        FILES_NEW=$(echo "''${BACKUP_OUTPUT}" | grep -oP 'Added to the repository: \K[\d.]+\s+\w+' || echo "N/A")
        FILES_CHANGED=$(echo "''${BACKUP_OUTPUT}" | grep -oP 'processed \K\d+ files' || echo "N/A")

        # Build success email
        EMAIL_BODY="✅ Backup completed successfully!

        Hostname: ''${HOSTNAME}
        Backup Paths: ''${BACKUP_PATHS}
        Repository: ${cfg.repoPath}
        Duration: ''${DURATION_MIN}m ''${DURATION_SEC}s
        Completed: $(date)

        === Backup Summary ===
        ''${FILES_CHANGED}
        Data Added: ''${FILES_NEW}

        === Retention Policy ===
        Daily: ${toString cfg.retention.keepDaily}
        Weekly: ${toString cfg.retention.keepWeekly}
        Monthly: ${toString cfg.retention.keepMonthly}

        === Repository Stats ===
        ''${STATS_OUTPUT}

        === Recent Snapshots ===
        $(restic snapshots --compact | tail -10)

        Check full logs: journalctl -u backup-var-lib.service
        "

        log "Backup completed successfully in ''${DURATION_MIN}m ''${DURATION_SEC}s"

        # Send success email
        send_email "✅ Backup Successful on ''${HOSTNAME}" "''${EMAIL_BODY}"
  '';
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.system.backupVarLib = {
    enable = mkEnableOption "Encrypted restic backup to Hetzner Storage Box (SMB)";

    paths = mkOption {
      type = types.listOf types.str;
      default = ["/var/lib"];
      description = "Absolute paths to include in the restic backup.";
      example = ["/var/lib" "/data" "/etc" "/home"];
    };

    excludes = mkOption {
      type = types.listOf types.str;
      default = [
        "/var/lib/docker/overlay2"
        "/var/lib/containers/storage/overlay"
        "/var/lib/systemd/coredump"
        "*.tmp"
        "*.cache"
      ];
      description = "Patterns passed to restic --exclude for every backup run.";
    };

    mountPoint = mkOption {
      type = types.str;
      default = "/mnt/galadriel-local-backup";
      description = "Mount point for the SMB share";
    };

    smbMountOptions = mkOption {
      type = types.str;
      default = "vers=3.0,nosuid,nodev,noexec,uid=0,gid=0,dir_mode=0700,file_mode=0600";
      description = "Extra mount.cifs -o options (username/password appended by the script).";
      example = "vers=3.1.1,seal,nosuid,nodev,noexec,uid=0,gid=0,dir_mode=0700,file_mode=0600";
    };

    repoPath = mkOption {
      type = types.str;
      default = "${config.fleet.system.backupVarLib.mountPoint}/${config.networking.hostName}/restic/system";
      description = "Path to the restic repository on the mounted share";
    };

    timeout = mkOption {
      type = types.str;
      default = "4h";
      description = "Maximum runtime for a single backup job (systemd TimeoutStartSec).";
      example = "24h";
    };

    memoryMax = mkOption {
      type = types.str;
      default = "2G";
      description = "Memory limit for the backup service.";
    };

    schedule = mkOption {
      type = types.str;
      default = "daily";
      description = "Systemd timer schedule (OnCalendar format)";
      example = "daily";
    };

    retention = {
      keepDaily = mkOption {
        type = types.int;
        default = 7;
        description = "Number of daily backups to keep";
      };

      keepWeekly = mkOption {
        type = types.int;
        default = 4;
        description = "Number of weekly backups to keep";
      };

      keepMonthly = mkOption {
        type = types.int;
        default = 6;
        description = "Number of monthly backups to keep";
      };
    };

    email = {
      to = mkOption {
        type = types.str;
        default = "admin@sn0wstorm.com";
        description = "Email address to send backup reports to";
      };

      from = mkOption {
        type = types.str;
        default = "Backup <backup@sn0wstorm.com>";
        description = "Email sender address";
      };

      smtp = {
        host = mkOption {
          type = types.str;
          default = "mail.sn0wstorm.com";
          description = "SMTP server hostname";
        };

        port = mkOption {
          type = types.port;
          default = 587;
          description = "SMTP server port";
        };

        usernameFile = mkOption {
          type = types.path;
          default = "/run/secrets/backup/smtp/username";
          description = "Path to file containing SMTP username";
        };

        passwordFile = mkOption {
          type = types.path;
          default = "/run/secrets/backup/smtp/password";
          description = "Path to file containing SMTP password";
        };

        tls = {
          skipVerify = mkOption {
            type = types.bool;
            default = false;
            description = "Skip TLS certificate verification (not recommended)";
          };

          minimumVersion = mkOption {
            type = types.str;
            default = "TLS1.2";
            description = "Minimum TLS version";
          };
        };
      };
    };

    secrets = {
      smbShareFile = mkOption {
        type = types.path;
        default = "/run/secrets/hetzner_smb/share";
        description = "Path to file containing SMB share path";
      };

      smbUsernameFile = mkOption {
        type = types.path;
        default = "/run/secrets/hetzner_smb/username";
        description = "Path to file containing SMB username";
      };

      smbPasswordFile = mkOption {
        type = types.path;
        default = "/run/secrets/hetzner_smb/password";
        description = "Path to file containing SMB password";
      };

      resticPasswordFile = mkOption {
        type = types.path;
        default = "/run/secrets/backup/restic/password";
        description = "Path to file containing restic repository password";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # Install required packages
    environment.systemPackages = with pkgs; [
      restic
      cifs-utils
      msmtp
    ];

    # Systemd service for backup
    systemd.services.backup-var-lib = {
      description = "Encrypted restic backup to Hetzner Storage Box";

      # Avoid overlapping with other heavy jobs; serialized via timer only.
      after = ["network-online.target"];
      wants = ["network-online.target"];

      path = with pkgs; [cifs-utils restic msmtp];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupScript}";
        User = "root";
        Group = "root";

        PrivateTmp = true;

        # Keep disk load low — important on galadriel's LVM spanning HDD.
        Nice = 10;
        IOSchedulingClass = "idle";
        CPUQuota = "80%";
        MemoryMax = cfg.memoryMax;
        IOWeight = 50;

        TimeoutStartSec = cfg.timeout;
      };
    };

    systemd.timers.backup-var-lib = {
      description = "Timer for Hetzner restic backup";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };

    # Create mount point and log directory
    systemd.tmpfiles.rules = [
      "d /var/log 0755 root root -"
      "d ${cfg.mountPoint} 0700 root root -"
    ];
  };
}
