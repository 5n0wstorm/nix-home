{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.dev.jenkins;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.dev.jenkins = {
    enable = mkEnableOption "Jenkins CI/CD server";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for Jenkins web interface";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address for Jenkins to listen on";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # Register with reverse proxy service registry
    fleet.networking.reverseProxy.serviceRegistry.jenkins = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = "jenkins.sn0wstorm.com";
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.websockets" = "true";
        "fleet.reverse-proxy.extra-config" = ''
          client_max_body_size 500M;
          proxy_read_timeout 300;
          proxy_send_timeout 300;
        '';
      };
    };

    # --------------------------------------------------------------------------
    # JENKINS SERVICE
    # --------------------------------------------------------------------------

    services.jenkins = {
      enable = true;
      listenAddress = cfg.listenAddress;
      port = cfg.port;
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
