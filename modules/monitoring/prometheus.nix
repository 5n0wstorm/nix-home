{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.monitoring.prometheus;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.monitoring.prometheus = {
    enable = mkEnableOption "Prometheus monitoring server";

    port = mkOption {
      type = types.port;
      default = 9090;
      description = "Port for Prometheus web interface";
    };

    scrapeConfigs = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "Additional scrape configurations";
    };

    nodeExporterTargets = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of node exporter targets (host:port)";
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
        default = "Prometheus";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Metrics collection & alerting";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-prometheus";
        description = "Icon for homepage (mdi-*, si-*, or URL)";
      };

      category = mkOption {
        type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
        default = "Monitoring";
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

    fleet.apps.homepage.serviceRegistry.prometheus = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://prometheus.sn0wstorm.com";
      category = cfg.homepage.category;
      widget = {
        type = "prometheus";
        url = "http://localhost:${toString cfg.port}";
        fields = ["targets_up" "targets_down" "targets_total"];
      };
    };

    # --------------------------------------------------------------------------
    # PROMETHEUS SERVICE
    # --------------------------------------------------------------------------

    services.prometheus = {
      enable = true;
      port = cfg.port;

      scrapeConfigs =
        [
          # Self-monitoring
          {
            job_name = "prometheus";
            static_configs = [
              {
                targets = ["localhost:${toString cfg.port}"];
              }
            ];
          }

          # Node exporters - auto-discover fleet hosts
          {
            job_name = "node-exporter";
            static_configs = [
              {
                targets = cfg.nodeExporterTargets;
              }
            ];
          }
        ]
        ++ cfg.scrapeConfigs;
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port];

    # ----------------------------------------------------------------------------
    # REVERSE PROXY SERVICE REGISTRATION
    # ----------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry."prometheus" = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = "prometheus.sn0wstorm.com";
        "fleet.reverse-proxy.ssl" = "true";
      };
    };
  };
}
