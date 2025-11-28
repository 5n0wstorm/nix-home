{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.fleet.monitoring.prometheus;
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
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
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
  };
}
