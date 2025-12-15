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

    usernameFile = mkOption {
      type = types.path;
      description = "Path to file containing the SMB username (from sops-nix)";
    };

    passwordFile = mkOption {
      type = types.path;
      description = "Path to file containing the SMB password (from sops-nix)";
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
    # ==========================================================================
    # SAMBA SERVICE
    # ==========================================================================

    services.samba = {
      enable = true;
      openFirewall = cfg.openFirewall;

      # Ensure state directory exists
      enableWinbindd = false;
      enableNmbd = true;

      settings = {
        global = {
          security = "user";
          "server string" = "NixOS Samba Server";
          "workgroup" = "WORKGROUP";
          "server role" = "standalone server";
          "map to guest" = "never";
          "hosts allow" = concatStringsSep " " cfg.allowedNetworks;
          "hosts deny" = "0.0.0.0/0";

          # SMB2+ only (disable SMB1 for security)
          "server min protocol" = "SMB2";
          "client min protocol" = "SMB2";

          # Performance tuning
          "socket options" = "TCP_NODELAY IPTOS_LOWDELAY";
          "read raw" = "yes";
          "write raw" = "yes";
          "max xmit" = "65535";
          "dead time" = "15";
          "getwd cache" = "yes";

          # Logging
          "log level" = "1";
          "log file" = "/var/log/samba/%m.log";
          "max log size" = "50";
        };

        # Data share configuration
        ${cfg.shareName} = {
          path = cfg.path;
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "@smb-data";
          "force group" = "smb-data";
          "create mask" = "0664";
          "directory mask" = "0775";
          browseable = "yes";
          writable = "yes";
          "vfs objects" = "acl_xattr";
          "map acl inherit" = "yes";
          "store dos attributes" = "yes";
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
    # USER/GROUP MANAGEMENT
    # ==========================================================================

    # Create static group for SMB users
    users.groups.smb-data = {};

    # ==========================================================================
    # STATE DIRECTORY
    # ==========================================================================

    # Ensure Samba state directories exist before services start
    systemd.tmpfiles.rules = [
      "d /var/lib/samba 0755 root root -"
      "d /var/lib/samba/private 0700 root root -"
    ];

    # ==========================================================================
    # PROVISIONING SERVICE
    # ==========================================================================

    systemd.services.samba-data-provision = {
      description = "Provision Samba user and ACLs for ${cfg.shareName} share";
      wantedBy = ["multi-user.target"];
      after = ["sops-nix.service" "local-fs.target" "systemd-tmpfiles-setup.service"];
      before = ["samba-smbd.service"];
      # Don't require - let Samba start even if provisioning fails initially
      # requiredBy = ["samba-smbd.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
      };

      path = with pkgs; [
        samba
        acl
        coreutils
        gnugrep
        gawk
        shadow
      ];

      script = ''
        set -euo pipefail

        # Ensure Samba directories exist
        mkdir -p /var/lib/samba/private
        chmod 700 /var/lib/samba/private

        # Read credentials from secret files
        if [ ! -f "${cfg.usernameFile}" ]; then
          echo "ERROR: Username file not found: ${cfg.usernameFile}"
          exit 1
        fi

        if [ ! -f "${cfg.passwordFile}" ]; then
          echo "ERROR: Password file not found: ${cfg.passwordFile}"
          exit 1
        fi

        SMB_USER=$(cat "${cfg.usernameFile}" | tr -d '\n\r')
        SMB_PASS=$(cat "${cfg.passwordFile}" | tr -d '\n\r')

        if [ -z "$SMB_USER" ]; then
          echo "ERROR: Username is empty"
          exit 1
        fi

        if [ -z "$SMB_PASS" ]; then
          echo "ERROR: Password is empty"
          exit 1
        fi

        echo "Provisioning Samba user: $SMB_USER"

        # Create Unix user if it doesn't exist
        if ! id "$SMB_USER" &>/dev/null; then
          echo "Creating Unix user: $SMB_USER"
          useradd --system --no-create-home --shell /sbin/nologin --groups smb-data "$SMB_USER"
        else
          echo "Unix user already exists: $SMB_USER"
          # Ensure user is in smb-data group
          if ! groups "$SMB_USER" | grep -q smb-data; then
            echo "Adding $SMB_USER to smb-data group"
            usermod -aG smb-data "$SMB_USER"
          fi
        fi

        # Create/update Samba user password (idempotent)
        if pdbedit -L | grep -q "^$SMB_USER:"; then
          echo "Updating Samba password for: $SMB_USER"
        else
          echo "Creating Samba user: $SMB_USER"
        fi
        printf '%s\n%s\n' "$SMB_PASS" "$SMB_PASS" | smbpasswd -a -s "$SMB_USER"
        smbpasswd -e "$SMB_USER"

        # Verify ACL support on the filesystem
        echo "Checking ACL support on ${cfg.path}"
        if ! touch "${cfg.path}/.acl_test" 2>/dev/null; then
          echo "ERROR: Cannot write to ${cfg.path}"
          exit 1
        fi

        if ! setfacl -m u:"$SMB_USER":rwx "${cfg.path}/.acl_test" 2>/dev/null; then
          rm -f "${cfg.path}/.acl_test"
          echo "ERROR: Filesystem at ${cfg.path} does not support POSIX ACLs"
          echo "Please ensure the filesystem is mounted with ACL support (e.g., ext4, xfs, btrfs)"
          exit 1
        fi
        rm -f "${cfg.path}/.acl_test"

        # Apply recursive ACLs for the SMB user
        echo "Applying recursive ACLs for $SMB_USER on ${cfg.path}"
        setfacl -R -m u:"$SMB_USER":rwx "${cfg.path}"

        # Apply default ACLs for new files/directories
        echo "Applying default ACLs for $SMB_USER on ${cfg.path}"
        find "${cfg.path}" -type d -exec setfacl -d -m u:"$SMB_USER":rwx {} \;

        echo "Samba provisioning complete for user: $SMB_USER"
      '';
    };

    # ==========================================================================
    # SYSTEM PACKAGES
    # ==========================================================================

    environment.systemPackages = with pkgs; [
      samba
      acl
    ];
  };
}
