{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.monitoring.grafana;
  homepageCfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.monitoring.grafana = {
    enable = mkEnableOption "Grafana monitoring dashboard";

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Grafana web interface";
    };

    prometheusUrl = mkOption {
      type = types.str;
      default = "http://localhost:9090";
      description = "URL of Prometheus server";
    };

    domain = mkOption {
      type = types.str;
      default = "localhost";
      description = "Domain name for Grafana";
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
        default = "Grafana";
        description = "Display name on homepage";
      };

      description = mkOption {
        type = types.str;
        default = "Metrics visualization & dashboards";
        description = "Description shown on homepage";
      };

      icon = mkOption {
        type = types.str;
        default = "si-grafana";
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

    fleet.apps.homepage.serviceRegistry.grafana = mkIf (cfg.homepage.enable && homepageCfg.enable) {
      name = cfg.homepage.name;
      description = cfg.homepage.description;
      icon = cfg.homepage.icon;
      href = "https://grafana.sn0wstorm.com";
      category = cfg.homepage.category;
      widget = {
        type = "grafana";
        url = "http://localhost:${toString cfg.port}";
        fields = ["dashboards" "datasources" "alertstriggered"];
      };
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.grafana = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = "grafana.sn0wstorm.com";
        "fleet.reverse-proxy.ssl" = "true";
        "fleet.reverse-proxy.websockets" = "false";
        "fleet.reverse-proxy.extra-config" = ''
          client_max_body_size 100M;
        '';
      };
    };

    # --------------------------------------------------------------------------
    # GRAFANA SERVICE
    # --------------------------------------------------------------------------

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = cfg.port;
          http_addr = "0.0.0.0";
          domain = cfg.domain;
          root_url = "http://${cfg.domain}:${toString cfg.port}/";
        };

        security = {
          admin_user = "admin";
          admin_password = "admin";
        };

        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
        };
      };

      provision = {
        enable = true;

        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = cfg.prometheusUrl;
            isDefault = true;
          }
        ];

        dashboards.settings.providers = [
          {
            name = "default";
            options.path = "/var/lib/grafana/dashboards";
          }
        ];
      };
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port];

    # --------------------------------------------------------------------------
    # DASHBOARD SETUP
    # --------------------------------------------------------------------------

    # Fetch the popular Node Exporter Full dashboard
    environment.etc."grafana/dashboards/node-exporter.json".source = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/rfmoz/grafana-dashboards/master/prometheus/node-exporter-full.json";
      sha256 = "sha256-lOpPVIW4Rih8/5zWnjC3K0kKgK5Jc1vQgCgj4CVkYP4=";
    };

    # Create directory for dashboards and copy our dashboard
    systemd.tmpfiles.rules = [
      "d /var/lib/grafana/dashboards 755 grafana grafana"
      "C /var/lib/grafana/dashboards/node-exporter.json 644 grafana grafana - /etc/grafana/dashboards/node-exporter.json"
    ];
  };
}
