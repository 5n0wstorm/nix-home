{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.apps.exampleService;
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
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # Register with reverse proxy service registry
    fleet.networking.reverseProxy.serviceRegistry.exampleService = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.ssl-type" = "acme";  # Use Let's Encrypt ACME certificates
        "fleet.reverse-proxy.websockets" = if cfg.websockets then "true" else "false";
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
