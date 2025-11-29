{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.media.jellyfin;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.jellyfin = {
    enable = mkEnableOption "Jellyfin media server";

    port = mkOption {
      type = types.port;
      default = 8096;
      description = "Port for Jellyfin web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "jellyfin.local";
      description = "Domain name for Jellyfin";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/jellyfin";
      description = "Data directory for Jellyfin";
    };

    mediaDir = mkOption {
      type = types.str;
      default = "/media";
      description = "Media directory for Jellyfin";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Jellyfin";
    };

    bypassAuth = mkOption {
      type = types.bool;
      default = true;
      description = "Bypass Authelia authentication (Jellyfin has built-in auth)";
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
        default = "Jellyfin";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Media streaming server";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-jellyfin";
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

    fleet.apps.homepage.serviceRegistry.jellyfin = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "jellyfin";
        url = "http://localhost:${toString cfg.port}";
        fields = ["movies" "series" "episodes"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.jellyfin = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.websockets" = "true";
        "fleet.authelia.bypass" =
          if cfg.bypassAuth
          then "true"
          else "false";
      };
    };

    # --------------------------------------------------------------------------
    # JELLYFIN SERVICE
    # --------------------------------------------------------------------------

    services.jellyfin = {
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
