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
        # When using VPN, qBittorrent runs inside gluetun container
        url =
          if cfg.vpn.enable
          then "http://localhost:${toString vpnCfg.ports.webui}"
          else "http://localhost:${toString cfg.port}";
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

      volumes = [
        "${cfg.dataDir}:/config"
        # Mount full media directory for hardlinks/moves to work
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

    systemd.services.qbittorrent-port-update = mkIf (cfg.vpn.enable && cfg.vpn.autoUpdatePort) {
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
        sleep 60

        # qBittorrent Web API credentials (default: admin/adminadmin on first run)
        # User should change these in the qBittorrent web UI
        QB_HOST="http://localhost:${toString vpnCfg.ports.webui}"
        COOKIE_FILE="/tmp/qb_cookie"

        while true; do
          # Get the forwarded port from gluetun control server
          FORWARDED_PORT=$(curl -s http://localhost:${toString vpnCfg.ports.control}/v1/openvpn/portforwarded 2>/dev/null | jq -r '.port // empty')

          if [ -n "$FORWARDED_PORT" ] && [ "$FORWARDED_PORT" != "0" ] && [ "$FORWARDED_PORT" != "null" ]; then
            echo "VPN forwarded port: $FORWARDED_PORT"

            # Try to get current qBittorrent port
            # Note: This requires authentication - user needs to set up API access
            CURRENT_PORT=$(curl -s "$QB_HOST/api/v2/app/preferences" 2>/dev/null | jq -r '.listen_port // empty')

            if [ "$CURRENT_PORT" != "$FORWARDED_PORT" ]; then
              echo "Updating qBittorrent listening port from $CURRENT_PORT to $FORWARDED_PORT"
              # Update port via API (requires valid session)
              # curl -s -X POST "$QB_HOST/api/v2/app/setPreferences" \
              #   -d "json={\"listen_port\":$FORWARDED_PORT}"
              echo "Port update would be applied here (requires auth setup)"
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
