{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.media.radarr;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.radarr = {
    enable = mkEnableOption "Radarr movie management";

    port = mkOption {
      type = types.port;
      default = 7878;
      description = "Port for Radarr web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "radarr.local";
      description = "Domain name for Radarr";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/radarr";
      description = "Data directory for Radarr";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Radarr";
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
        default = "Radarr";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Movie manager";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-radarr";
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

    fleet.apps.homepage.serviceRegistry.radarr = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "radarr";
        url = "http://localhost:${toString cfg.port}";
        fields = ["wanted" "queued" "movies"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.radarr = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # RADARR SERVICE
    # --------------------------------------------------------------------------

    services.radarr = {
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

