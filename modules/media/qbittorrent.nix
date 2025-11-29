{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.media.qbittorrent;
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
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.qbittorrent = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "qbittorrent";
        url = "http://localhost:${toString cfg.port}";
        fields = ["leech" "download" "seed" "upload"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.qbittorrent = {
      port = cfg.port;
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
    };

    users.groups.${cfg.group} = {};

    # --------------------------------------------------------------------------
    # DATA DIRECTORY SETUP
    # --------------------------------------------------------------------------

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.downloadDir} 0775 ${cfg.user} ${cfg.group} -"
    ];

    # --------------------------------------------------------------------------
    # QBITTORRENT SERVICE
    # --------------------------------------------------------------------------

    systemd.services.qbittorrent = {
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
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port cfg.torrentPort];
      allowedUDPPorts = [cfg.torrentPort];
    };
  };
}
