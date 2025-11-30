{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.dev.jenkins;
  homepageCfg = config.fleet.apps.homepage;
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

    # Homepage dashboard integration
    homepage = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Register this service with the homepage dashboard";
      };

      name = mkOption {
        type = types.str;
        default = "Jenkins";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "CI/CD automation server";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-jenkins";
        description = "Icon for homepage (mdi-*, si-*, or URL)";
      };

      category = mkOption {
        type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
        default = "Dev";
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

    fleet.apps.homepage.serviceRegistry.jenkins = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://jenkins.sn0wstorm.com";
      category = cfg.homepage.category;
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

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
