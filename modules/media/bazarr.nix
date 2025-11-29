{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.media.bazarr;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.bazarr = {
    enable = mkEnableOption "Bazarr subtitle management";

    port = mkOption {
      type = types.port;
      default = 6767;
      description = "Port for Bazarr web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "bazarr.local";
      description = "Domain name for Bazarr";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Bazarr";
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
        default = "Bazarr";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Subtitle manager";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-bazarr";
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

    fleet.apps.homepage.serviceRegistry.bazarr = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "bazarr";
        url = "http://localhost:${toString cfg.port}";
        fields = ["missingEpisodes" "missingMovies"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.bazarr = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # BAZARR SERVICE
    # --------------------------------------------------------------------------

    services.bazarr = {
      enable = true;
      openFirewall = cfg.openFirewall;
      listenPort = cfg.port;
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}

