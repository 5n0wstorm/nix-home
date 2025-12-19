{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.apps.cockpit;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.cockpit = {
    enable = mkEnableOption "Cockpit web-based server management interface";

    port = mkOption {
      type = types.port;
      default = 9090;
      description = "Port for Cockpit web interface";
    };

    domain = mkOption {
      type = types.str;
      default = "cockpit.local";
      description = "Domain name for Cockpit";
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
        default = "Cockpit";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Server management";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-cockpit";
        description = "Icon for homepage (mdi-*, si-*, or URL)";
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
    # HOMEPAGE DASHBOARD REGISTRATION
    # --------------------------------------------------------------------------

    fleet.apps.homepage.serviceRegistry.cockpit = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.cockpit = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.scheme" = "https";
        "fleet.reverse-proxy.websockets" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # AUTHELIA TWO-FACTOR ENFORCEMENT
    # --------------------------------------------------------------------------
    # Add Cockpit domain to two-factor domains for enhanced security

    fleet.security.authelia.twoFactorDomains = [cfg.domain];

    # --------------------------------------------------------------------------
    # COCKPIT SERVICE
    # --------------------------------------------------------------------------

    services.cockpit = {
      enable = true;
      port = cfg.port;
      openFirewall = false; # nginx reverse proxy handles external access

      # Allow the proxied domain to avoid CORS/origin issues
      allowed-origins = ["https://${cfg.domain}"];
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
