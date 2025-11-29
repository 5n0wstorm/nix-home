{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.apps.exampleService;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.exampleService = {
    enable = mkEnableOption "Example service for demonstrating pluggable reverse proxy";

    port = mkOption {
      type = types.port;
      default = 8081;
      description = "Port for the example service";
    };

    domain = mkOption {
      type = types.str;
      default = "example.local";
      description = "Domain name for the service";
    };

    websockets = mkOption {
      type = types.bool;
      default = false;
      description = "Enable websocket support";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Additional nginx configuration";
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
        default = "Example Service";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Demo service for reverse proxy";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "mdi-application";
        description = "Icon for homepage (mdi-*, si-*, or URL)";
      };

      category = mkOption {
        type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
        default = "Services";
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

    fleet.apps.homepage.serviceRegistry.exampleService = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://${cfg.domain}";
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.exampleService = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.ssl-type" = "acme"; # Use Let's Encrypt ACME certificates
        "fleet.reverse-proxy.websockets" =
          if cfg.websockets
          then "true"
          else "false";
        "fleet.reverse-proxy.extra-config" = cfg.extraConfig;
      };
    };

    # --------------------------------------------------------------------------
    # EXAMPLE SERVICE (placeholder - replace with real service)
    # --------------------------------------------------------------------------

    # This would be a real service like:
    # services.exampleService = {
    #   enable = true;
    #   port = cfg.port;
    # };

    # For now, we'll create a simple systemd service that serves a static page
    systemd.services.example-service = {
      description = "Example service for pluggable reverse proxy demo";
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString cfg.port}";
        WorkingDirectory = "/tmp";
        User = "nobody";
        Group = "nogroup";
      };
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
