{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.networking.sambaDataShare;
in {
  # ============================================================================
  # OPTIONS
  # ============================================================================

  options.fleet.networking.sambaDataShare = {
    enable = mkEnableOption "Samba share for /data directory";

    shareName = mkOption {
      type = types.str;
      default = "data";
      description = "Name of the SMB share";
    };

    path = mkOption {
      type = types.path;
      default = "/data";
      description = "Path to the directory to share";
    };

    username = mkOption {
      type = types.str;
      example = "chef";
      description = "Unix/Samba username for the share (declared via users.users)";
    };

    passwordFile = mkOption {
      type = types.path;
      description = "Path to file containing the SMB password (from sops-nix)";
    };

    dataGroup = mkOption {
      type = types.str;
      default =
        if config.fleet.media.shared.enable or false
        then config.fleet.media.shared.group
        else "media";
      description = ''
        POSIX group used for share access. Should match fleet.media.shared.group
        so standard directory modes on /data apply without ACLs.
      '';
    };

    allowedNetworks = mkOption {
      type = types.listOf types.str;
      default = ["192.168.2.0/24" "127.0.0.1"];
      description = "List of networks/IPs allowed to access the share";
      example = ["192.168.1.0/24" "10.0.0.0/8"];
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open firewall ports for Samba";
    };

    wsdd = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Web Services Dynamic Discovery (for Windows network discovery)";
      };
    };
  };

  # ============================================================================
  # CONFIGURATION
  # ============================================================================

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.username != "";
        message = "fleet.networking.sambaDataShare.username must be set when Samba is enabled";
      }
    ];

    # ==========================================================================
    # SAMBA SERVICE
    # ==========================================================================

    services.samba = {
      enable = true;
      openFirewall = cfg.openFirewall;

      nmbd.enable = true;
      winbindd.enable = false;

      settings = {
        global = {
          security = "user";
          "server string" = "NixOS Samba Server";
          "workgroup" = "WORKGROUP";
          "server role" = "standalone server";
          "map to guest" = "never";
          "hosts allow" = concatStringsSep " " cfg.allowedNetworks;
          "hosts deny" = "0.0.0.0/0";

          "server min protocol" = "SMB2";
          "client min protocol" = "SMB2";

          "socket options" = "TCP_NODELAY IPTOS_LOWDELAY";
          "read raw" = "yes";
          "write raw" = "yes";
          "max xmit" = "65535";
          "dead time" = "15";
          "getwd cache" = "yes";
          "csc policy" = "disable";

          "log level" = "1";
          "log file" = "/var/log/samba/%m.log";
          "max log size" = "50";
        };

        ${cfg.shareName} = {
          path = cfg.path;
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = cfg.username;
          "force group" = cfg.dataGroup;
          "create mask" = "0664";
          "directory mask" = "0775";
          browseable = "yes";
          writable = "yes";
          "store dos attributes" = "yes";

          "oplocks" = "no";
          "level2 oplocks" = "no";
          "strict locking" = "yes";
        };
      };
    };

    # ==========================================================================
    # WSDD - Windows Network Discovery
    # ==========================================================================

    services.samba-wsdd = mkIf cfg.wsdd.enable {
      enable = true;
      openFirewall = cfg.openFirewall;
    };

    # ==========================================================================
    # USER MANAGEMENT (POSIX permissions via shared media group)
    # ==========================================================================

    users.users.${cfg.username} = {
      isSystemUser = true;
      group = cfg.dataGroup;
      home = "/var/empty";
      createHome = false;
    };

    # ==========================================================================
    # STATE DIRECTORY
    # ==========================================================================

    systemd.tmpfiles.rules = [
      "d /var/lib/samba 0755 root root -"
      "d /var/lib/samba/private 0700 root root -"
    ];

    # ==========================================================================
    # SAMBA PASSWORD SYNC
    # Samba passwords live in a separate ldb — sync from sops on activation.
    # ==========================================================================

    systemd.services.samba-password-sync = {
      description = "Sync Samba password for ${cfg.username}";
      wantedBy = ["multi-user.target"];
      after = ["sops-nix.service"];
      before = ["samba-smbd.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      path = [pkgs.samba];

      script = ''
        set -euo pipefail

        if [ ! -f "${cfg.passwordFile}" ]; then
          echo "ERROR: Password file not found: ${cfg.passwordFile}"
          exit 1
        fi

        SMB_PASS=$(tr -d '\n\r' < "${cfg.passwordFile}")
        if [ -z "$SMB_PASS" ]; then
          echo "ERROR: Samba password is empty"
          exit 1
        fi

        if pdbedit -L 2>/dev/null | grep -q '^${cfg.username}:'; then
          echo "Updating Samba password for ${cfg.username}"
        else
          echo "Creating Samba user ${cfg.username}"
        fi

        printf '%s\n%s\n' "$SMB_PASS" "$SMB_PASS" | smbpasswd -a -s ${cfg.username}
        smbpasswd -e ${cfg.username}
      '';
    };

    environment.systemPackages = [pkgs.samba];
  };
}
