{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.media.qbittorrent;
  vpnCfg = config.fleet.networking.vpnGateway;
  sharedCfg = config.fleet.media.shared;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.qbittorrent = {
    enable = mkEnableOption "qBittorrent download client";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for qBittorrent web interface";
    };

    torrentPort = mkOption {
      type = types.port;
      default = 6881;
      description = "Port for BitTorrent connections";
    };

    domain = mkOption {
      type = types.str;
      default = "qbittorrent.local";
      description = "Domain name for qBittorrent";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/qbittorrent";
      description = "Data directory for qBittorrent";
    };

    downloadDir = mkOption {
      type = types.str;
      default = "/media/downloads";
      description = "Download directory for qBittorrent";
    };

    user = mkOption {
      type = types.str;
      default = "qbittorrent";
      description = "User to run qBittorrent as";
    };

    group = mkOption {
      type = types.str;
      default = "qbittorrent";
      description = "Group to run qBittorrent as";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for qBittorrent";
    };

    # VPN routing configuration
    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Route all qBittorrent traffic through VPN gateway";
      };

      autoUpdatePort = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically update qBittorrent listening port from VPN port forwarding";
      };

      # Credentials for qBittorrent API (needed for auto port update)
      apiUsername = mkOption {
        type = types.str;
        default = "admin";
        description = "qBittorrent Web UI username for API access";
      };

      apiPasswordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to file containing qBittorrent Web UI password for API access";
        example = "/run/secrets/qbittorrent/password";
      };
    };

    # Homepage dashboard integration
    homepage = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Register this service with the homepage dashboard";
      };

      name = mkOption {
        type = types.str;
        default = "qBittorrent";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Torrent client";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-qbittorrent";
        description = "Icon for homepage";
      };

      category = mkOption {
        type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
        default = "Media";
        description = "Category on the homepage dashboard";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # ASSERTIONS
    # --------------------------------------------------------------------------

    assertions = [
      {
        assertion = cfg.vpn.enable -> vpnCfg.enable;
        message = "VPN gateway must be enabled (fleet.networking.vpnGateway.enable = true) when using VPN routing for qBittorrent";
      }
    ];

    # --------------------------------------------------------------------------
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.qbittorrent = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description =
        if cfg.vpn.enable
        then "${cfg.homepage.description} (VPN protected)"
        else cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "qbittorrent";
        # Use public URL for consistent access (localhost from container network has issues)
        url = "https://${cfg.domain}";
        fields = ["leech" "download" "seed" "upload"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.qbittorrent = {
      # When using VPN, the web UI is exposed from gluetun
      port =
        if cfg.vpn.enable
        then vpnCfg.ports.webui
        else cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # USER AND GROUP SETUP
    # --------------------------------------------------------------------------

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      # Assign UID for container user mapping
      uid = 2000;
      # Add to media group for shared directory access
      extraGroups = mkIf sharedCfg.enable [sharedCfg.group];
    };

    users.groups.${cfg.group} = {
      gid = 2000;
    };

    # --------------------------------------------------------------------------
    # DATA DIRECTORY SETUP
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.downloadDir} 0775 ${cfg.user} ${cfg.group} -"
    ];

    # --------------------------------------------------------------------------
    # QBITTORRENT SERVICE (NON-VPN MODE)
    # --------------------------------------------------------------------------

    systemd.services.qbittorrent = mkIf (!cfg.vpn.enable) {
      description = "qBittorrent-nox service";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox --webui-port=${toString cfg.port}";
        Restart = "on-failure";
        UMask = "0002";
      };
    };

    # --------------------------------------------------------------------------
    # QBITTORRENT CREDENTIALS PREPARATION SERVICE
    # Creates environment file with WebUI password from secrets
    # --------------------------------------------------------------------------

    systemd.services.qbittorrent-credentials = mkIf (cfg.vpn.enable && cfg.vpn.apiPasswordFile != null) {
      description = "Prepare qBittorrent WebUI credentials from secrets";
      before = ["podman-qbittorrent.service"];
      requiredBy = ["podman-qbittorrent.service"];
      wantedBy = ["multi-user.target"];

      path = [pkgs.coreutils];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Read password from secrets
        PASSWORD=$(cat ${cfg.vpn.apiPasswordFile} | tr -d '[:space:]')

        # Create environment file for qBittorrent container
        echo "WEBUI_USERNAME=${cfg.vpn.apiUsername}" > ${cfg.dataDir}/credentials.env
        echo "WEBUI_PASSWORD=$PASSWORD" >> ${cfg.dataDir}/credentials.env

        chmod 400 ${cfg.dataDir}/credentials.env
        echo "qBittorrent credentials prepared at ${cfg.dataDir}/credentials.env"
      '';
    };

    # --------------------------------------------------------------------------
    # QBITTORRENT CONTAINER (VPN MODE)
    # Routes all traffic through gluetun VPN container
    # --------------------------------------------------------------------------

    virtualisation.oci-containers.containers.qbittorrent = mkIf cfg.vpn.enable {
      image = "lscr.io/linuxserver/qbittorrent:latest";

      environment = {
        # Use media group GID for proper permissions
        PUID = "2000";
        PGID = toString (
          if sharedCfg.enable
          then sharedCfg.gid
          else 2000
        );
        TZ = "America/New_York";
        WEBUI_PORT = "8080";
      };

      # Load WebUI credentials from environment file (created by qbittorrent-credentials service)
      environmentFiles = mkIf (cfg.vpn.apiPasswordFile != null) [
        "${cfg.dataDir}/credentials.env"
      ];

      volumes = [
        "${cfg.dataDir}:/config"
        # Mount downloads directory to /downloads (qBittorrent default path)
        "${cfg.downloadDir}:/downloads"
        # Mount full media directory for hardlinks/moves to library folders
        "${
          if sharedCfg.enable
          then sharedCfg.baseDir
          else cfg.downloadDir
        }:/media"
      ];

      # Use gluetun's network namespace - ALL traffic goes through VPN
      dependsOn = [vpnCfg.containerName];
      extraOptions = [
        "--network=container:${vpnCfg.containerName}"
        "--pull=always"
      ];
    };

    # --------------------------------------------------------------------------
    # VPN PORT FORWARDING AUTO-UPDATE SERVICE
    # Automatically configures qBittorrent to use the VPN's forwarded port
    # --------------------------------------------------------------------------

    systemd.services.qbittorrent-port-update = mkIf (cfg.vpn.enable && cfg.vpn.autoUpdatePort && cfg.vpn.apiPasswordFile != null) {
      description = "Update qBittorrent listening port from VPN port forwarding";
      after = ["podman-qbittorrent.service" "vpn-port-monitor.service"];
      requires = ["podman-qbittorrent.service"];
      wantedBy = ["multi-user.target"];

      path = [pkgs.curl pkgs.jq pkgs.coreutils];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "60s";
      };

      script = ''
        # Wait for qBittorrent to be ready
        sleep 90

        # Use public URL - localhost connections from container network get 401
        QB_HOST="https://${cfg.domain}"
        QB_USER="${cfg.vpn.apiUsername}"
        QB_PASS_FILE="${cfg.vpn.apiPasswordFile}"
        COOKIE_FILE="/tmp/qb_cookie_$$"
        LAST_PORT=""

        cleanup() {
          rm -f "$COOKIE_FILE"
        }
        trap cleanup EXIT

        # URL encode a string (for special characters in password)
        urlencode() {
          local string="$1"
          local strlen=''${#string}
          local encoded=""
          local pos c o

          for (( pos=0 ; pos<strlen ; pos++ )); do
            c=''${string:$pos:1}
            case "$c" in
              [-_.~a-zA-Z0-9] ) o="$c" ;;
              * ) printf -v o '%%%02X' "'$c" ;;
            esac
            encoded+="$o"
          done
          echo "$encoded"
        }

        # Function to authenticate with qBittorrent
        qb_login() {
          if [ ! -f "$QB_PASS_FILE" ]; then
            echo "ERROR: Password file not found: $QB_PASS_FILE"
            return 1
          fi
          QB_PASS=$(cat "$QB_PASS_FILE" | tr -d '[:space:]')
          QB_PASS_ENCODED=$(urlencode "$QB_PASS")

          RESPONSE=$(curl -s -c "$COOKIE_FILE" -X POST "$QB_HOST/api/v2/auth/login" \
            -d "username=$QB_USER&password=$QB_PASS_ENCODED" 2>/dev/null)

          if [ "$RESPONSE" = "Ok." ]; then
            echo "Successfully authenticated with qBittorrent"
            return 0
          else
            echo "Failed to authenticate with qBittorrent: $RESPONSE"
            return 1
          fi
        }

        # Function to get current listening port
        qb_get_port() {
          curl -s -b "$COOKIE_FILE" "$QB_HOST/api/v2/app/preferences" 2>/dev/null | jq -r '.listen_port // empty'
        }

        # Function to set listening port
        qb_set_port() {
          local port=$1
          RESPONSE=$(curl -s -b "$COOKIE_FILE" -X POST "$QB_HOST/api/v2/app/setPreferences" \
            -d "json={\"listen_port\":$port}" 2>/dev/null)
          return $?
        }

        while true; do
          # Get the forwarded port from gluetun control server (-L follows redirects)
          FORWARDED_PORT=$(curl -sL "http://localhost:${toString vpnCfg.ports.control}/v1/openvpn/portforwarded" 2>/dev/null | jq -r '.port // empty')

          if [ -n "$FORWARDED_PORT" ] && [ "$FORWARDED_PORT" != "0" ] && [ "$FORWARDED_PORT" != "null" ]; then
            echo "VPN forwarded port: $FORWARDED_PORT"

            # Only update if port changed
            if [ "$FORWARDED_PORT" != "$LAST_PORT" ]; then
              # Authenticate with qBittorrent
              if qb_login; then
                CURRENT_PORT=$(qb_get_port)
                echo "Current qBittorrent listening port: $CURRENT_PORT"

                if [ "$CURRENT_PORT" != "$FORWARDED_PORT" ]; then
                  echo "Updating qBittorrent listening port from $CURRENT_PORT to $FORWARDED_PORT"
                  if qb_set_port "$FORWARDED_PORT"; then
                    echo "Successfully updated qBittorrent port to $FORWARDED_PORT"
                    LAST_PORT="$FORWARDED_PORT"
                  else
                    echo "Failed to update qBittorrent port"
                  fi
                else
                  echo "Port already set correctly"
                  LAST_PORT="$FORWARDED_PORT"
                fi
              fi
            fi
          else
            echo "Waiting for VPN port forwarding..."
          fi

          sleep 300  # Check every 5 minutes
        done
      '';
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall = mkIf (cfg.openFirewall && !cfg.vpn.enable) {
      allowedTCPPorts = [cfg.port cfg.torrentPort];
      allowedUDPPorts = [cfg.torrentPort];
    };
    # Note: When VPN is enabled, firewall rules are handled by the vpn-gateway module
  };
}
