{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.media.navidrome;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.navidrome = {
    enable = mkEnableOption "Navidrome music streaming server";

    port = mkOption {
      type = types.port;
      default = 4533;
      description = "Port for Navidrome web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "navidrome.local";
      description = "Domain name for Navidrome";
    };

    musicFolder = mkOption {
      type = types.str;
      default = "/media/music";
      description = "Music library folder";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Navidrome";
    };

    bypassAuth = mkOption {
      type = types.bool;
      default = true;
      description = "Bypass Authelia authentication (Navidrome has built-in auth)";
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
        default = "Navidrome";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Music streaming server";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-navidrome";
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

    fleet.apps.homepage.serviceRegistry.navidrome = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
      widget = {
        type = "navidrome";
        url = "http://localhost:${toString cfg.port}";
        fields = ["songs" "albums" "artists"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.navidrome = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.authelia.bypass" =
          if cfg.bypassAuth
          then "true"
          else "false";
      };
    };

    # --------------------------------------------------------------------------
    # NAVIDROME SERVICE
    # --------------------------------------------------------------------------

    services.navidrome = {
      enable = true;
      openFirewall = cfg.openFirewall;
      settings = {
        Port = cfg.port;
        MusicFolder = cfg.musicFolder;
        Address = "0.0.0.0";
      };
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}
