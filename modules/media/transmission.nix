{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.media.transmission;
  sharedCfg = config.fleet.media.shared;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.transmission = {
    enable = mkEnableOption "Transmission BitTorrent client";

    port = mkOption {
      type = types.port;
      default = 9091;
      description = "Port for Transmission web interface";
    };

    peerPort = mkOption {
      type = types.port;
      default = 51413;
      description = "Port for BitTorrent peer connections";
    };

    domain = mkOption {
      type = types.str;
      default = "transmission.local";
      description = "Domain name for Transmission";
    };

    downloadDir = mkOption {
      type = types.str;
      default =
        if sharedCfg.enable
        then sharedCfg.paths.torrents.root
        else "/data/torrents";
      description = "Download directory for Transmission (defaults to shared torrents path)";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Transmission";
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
        default = "Transmission";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Torrent client";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-transmission";
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
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.transmission = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "transmission";
        url = "http://localhost:${toString cfg.port}";
        fields = ["leech" "download" "seed" "upload"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.transmission = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # TRANSMISSION SERVICE
    # --------------------------------------------------------------------------

    services.transmission = {
      enable = true;
      openFirewall = cfg.openFirewall;
      openRPCPort = true;
      settings = {
        download-dir = cfg.downloadDir;
        rpc-port = cfg.port;
        rpc-bind-address = "0.0.0.0";
        rpc-whitelist-enabled = false;
        peer-port = cfg.peerPort;
        umask = 2;
      };
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port cfg.peerPort];
      allowedUDPPorts = [cfg.peerPort];
    };
  };
}
