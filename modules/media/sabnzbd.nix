{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.media.sabnzbd;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.sabnzbd = {
    enable = mkEnableOption "SABnzbd usenet downloader";

    port = mkOption {
      type = types.port;
      default = 8085;
      description = "Port for SABnzbd web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "sabnzbd.local";
      description = "Domain name for SABnzbd";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for SABnzbd";
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
        default = "SABnzbd";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Usenet downloader";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-sabnzbd";
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

    fleet.apps.homepage.serviceRegistry.sabnzbd = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "sabnzbd";
        url = "http://localhost:${toString cfg.port}";
        fields = ["rate" "queue" "timeleft"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.sabnzbd = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # SABNZBD SERVICE
    # --------------------------------------------------------------------------

    services.sabnzbd = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}

