{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.networking.vpnGateway;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.networking.vpnGateway = {
    enable = mkEnableOption "VPN gateway using Gluetun for secure traffic routing";

    provider = mkOption {
      type = types.enum ["private_internet_access" "mullvad" "nordvpn" "surfshark" "protonvpn" "custom"];
      default = "private_internet_access";
      description = "VPN provider to use";
    };

    # PIA-specific options
    pia = {
      serverRegions = mkOption {
        type = types.listOf types.str;
        default = ["netherlands"];
        description = "PIA server regions to connect to (comma-separated for multiple)";
      };

      portForwarding = mkOption {
        type = types.bool;
        default = true;
        description = "Enable PIA port forwarding (required for good torrent speeds)";
      };

      usernameFile = mkOption {
        type = types.str;
        default = "/run/secrets/pia-vpn/username";
        description = "Path to file containing PIA username";
      };

      passwordFile = mkOption {
        type = types.str;
        default = "/run/secrets/pia-vpn/password";
        description = "Path to file containing PIA password";
      };
    };

    # Network configuration
    vpnInterface = mkOption {
      type = types.str;
      default = "tun0";
      description = "VPN tunnel interface name";
    };

    dnsServers = mkOption {
      type = types.listOf types.str;
      default = ["1.1.1.1" "8.8.8.8"];
      description = "DNS servers to use when connected to VPN";
    };

    # Firewall/kill switch
    killSwitch = mkOption {
      type = types.bool;
      default = true;
      description = "Enable kill switch to block traffic if VPN disconnects";
    };

    # Health check
    healthCheck = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable periodic health checks";
      };

      url = mkOption {
        type = types.str;
        default = "https://ipinfo.io/ip";
        description = "URL to check for VPN connectivity";
      };
    };

    # Container settings
    containerName = mkOption {
      type = types.str;
      default = "gluetun";
      description = "Name of the Gluetun container";
    };

    # Port mappings for services routed through VPN
    ports = {
      webui = mkOption {
        type = types.port;
        default = 8088;
        description = "Port for qBittorrent web UI (exposed through VPN)";
      };

      torrent = mkOption {
        type = types.port;
        default = 6881;
        description = "Port for BitTorrent connections";
      };

      control = mkOption {
        type = types.port;
        default = 8000;
        description = "Port for Gluetun control server";
      };
    };

    # Port forwarding output (for dependent services)
    portForwardingStatusPath = mkOption {
      type = types.str;
      default = "/var/lib/gluetun/forwarded_port";
      description = "Path where the forwarded port number is written";
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
        default = "VPN Gateway";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Gluetun VPN tunnel";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-wireguard";
        description = "Icon for homepage";
      };

      category = mkOption {
        type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
        default = "Infrastructure";
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
        assertion = cfg.provider == "private_internet_access" -> (cfg.pia.usernameFile != "" && cfg.pia.passwordFile != "");
        message = "PIA username and password files must be specified when using Private Internet Access";
      }
    ];

    # --------------------------------------------------------------------------
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.vpn-gateway = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = ""; # No web UI
      category = cfg.homepage.category;
      widget = {
        type = "gluetun";
        url = "http://localhost:8000";
        fields = ["public_ip" "region" "country"];
      };
    };

    # --------------------------------------------------------------------------
    # DATA DIRECTORY SETUP
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      "d /var/lib/gluetun 0755 root root -"
    ];

    # --------------------------------------------------------------------------
    # CREDENTIALS PREPARATION SERVICE
    # Converts SOPS secrets to Gluetun environment file format
    # --------------------------------------------------------------------------

    systemd.services.gluetun-credentials = mkIf (cfg.provider == "private_internet_access") {
      description = "Prepare Gluetun VPN credentials from SOPS secrets";
      before = ["podman-${cfg.containerName}.service"];
      requiredBy = ["podman-${cfg.containerName}.service"];
      after = ["sops-nix.service"];
      wantedBy = ["multi-user.target"];

      path = [pkgs.coreutils];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Read credentials from SOPS secrets
        USERNAME=$(cat ${cfg.pia.usernameFile} | tr -d '[:space:]')
        PASSWORD=$(cat ${cfg.pia.passwordFile} | tr -d '[:space:]')

        # Create environment file for Gluetun in persistent directory
        echo "OPENVPN_USER=$USERNAME" > /var/lib/gluetun/credentials.env
        echo "OPENVPN_PASSWORD=$PASSWORD" >> /var/lib/gluetun/credentials.env

        chmod 400 /var/lib/gluetun/credentials.env
        echo "Gluetun credentials prepared at /var/lib/gluetun/credentials.env"
      '';
    };

    # --------------------------------------------------------------------------
    # VIRTUALIZATION SETUP
    # --------------------------------------------------------------------------

    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };
    };
    virtualisation.oci-containers.backend = "podman";

    # --------------------------------------------------------------------------
    # GLUETUN VPN CONTAINER
    # --------------------------------------------------------------------------

    virtualisation.oci-containers.containers.${cfg.containerName} = {
      image = "qmcgaw/gluetun:latest";

      # Environment configuration for PIA
      environment = mkIf (cfg.provider == "private_internet_access") {
        # VPN provider
        VPN_SERVICE_PROVIDER = "private internet access";
        VPN_TYPE = "openvpn"; # PIA works best with OpenVPN for port forwarding

        # Server selection
        SERVER_REGIONS = concatStringsSep "," cfg.pia.serverRegions;

        # Port forwarding
        VPN_PORT_FORWARDING =
          if cfg.pia.portForwarding
          then "on"
          else "off";
        VPN_PORT_FORWARDING_PROVIDER = "private internet access";

        # DNS
        DOT = "off"; # Use custom DNS
        DNS_ADDRESS = builtins.elemAt cfg.dnsServers 0;

        # Kill switch
        FIREWALL_VPN_INPUT_PORTS = ""; # Will be set by port forwarding

        # Health check
        HEALTH_VPN_DURATION_INITIAL = "30s";
        HEALTH_VPN_DURATION_ADDITION = "10s";

        # Timezone
        TZ = "America/New_York";
      };

      # Credentials from generated environment file
      environmentFiles = ["/var/lib/gluetun/credentials.env"];

      volumes = [
        "/var/lib/gluetun:/gluetun"
      ];

      # Required capabilities for VPN
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun:/dev/net/tun"
        "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
        "--pull=always"
        # Health check
        "--health-cmd=/gluetun-entrypoint healthcheck"
        "--health-interval=30s"
        "--health-retries=3"
        "--health-start-period=60s"
        "--health-timeout=10s"
      ];

      # Expose ports for services that will route through VPN
      # qBittorrent web UI and BitTorrent ports
      ports = [
        "${toString cfg.ports.webui}:8080" # qBittorrent Web UI (internal container port 8080)
        "${toString cfg.ports.torrent}:${toString cfg.ports.torrent}" # BitTorrent TCP
        "${toString cfg.ports.torrent}:${toString cfg.ports.torrent}/udp" # BitTorrent UDP
        "${toString cfg.ports.control}:8000" # Gluetun control server (for monitoring)
      ];
    };

    # --------------------------------------------------------------------------
    # PORT FORWARDING MONITOR SERVICE
    # --------------------------------------------------------------------------

    # Service to monitor and export the forwarded port
    systemd.services.vpn-port-monitor = mkIf cfg.pia.portForwarding {
      description = "Monitor VPN forwarded port and export for qBittorrent";
      after = ["podman-${cfg.containerName}.service"];
      requires = ["podman-${cfg.containerName}.service"];
      wantedBy = ["multi-user.target"];

      path = [pkgs.curl pkgs.jq pkgs.coreutils];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "30s";
      };

      script = ''
        while true; do
          # Wait for gluetun to be ready
          sleep 30

          # Get the forwarded port from gluetun control server (-L follows redirects)
          PORT=$(curl -sL "http://localhost:${toString cfg.ports.control}/v1/openvpn/portforwarded" 2>/dev/null | jq -r '.port // empty')

          if [ -n "$PORT" ] && [ "$PORT" != "0" ]; then
            echo "$PORT" > ${cfg.portForwardingStatusPath}
            echo "VPN forwarded port: $PORT"

            # Update qBittorrent if it's running
            # qBittorrent API call to update listening port would go here
            # This requires qBittorrent to be configured first
          else
            echo "Waiting for port forwarding..."
          fi

          sleep 60
        done
      '';
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    # The gluetun container handles its own firewall/kill switch
    # We just need to allow the exposed ports on the host
    networking.firewall = {
      allowedTCPPorts = [cfg.ports.webui cfg.ports.torrent cfg.ports.control];
      allowedUDPPorts = [cfg.ports.torrent];
    };
  };
}
