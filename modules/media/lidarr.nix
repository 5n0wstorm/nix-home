{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.media.lidarr;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.lidarr = {
    enable = mkEnableOption "Lidarr music management";

    port = mkOption {
      type = types.port;
      default = 8686;
      description = "Port for Lidarr web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "lidarr.local";
      description = "Domain name for Lidarr";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/lidarr";
      description = "Data directory for Lidarr";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Lidarr";
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
        default = "Lidarr";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Music manager";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-lidarr";
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

    fleet.apps.homepage.serviceRegistry.lidarr = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "lidarr";
        url = "http://localhost:${toString cfg.port}";
        fields = ["wanted" "queued" "artists"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.lidarr = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # LIDARR SERVICE
    # --------------------------------------------------------------------------

    services.lidarr = {
      enable = true;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.dataDir;
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}
