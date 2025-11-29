{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.apps.homepage;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.apps.homepage = {
    enable = mkEnableOption "Homepage dashboard for fleet services";

    port = mkOption {
      type = types.port;
      default = 8082;
      description = "Port for Homepage dashboard";
    };

    domain = mkOption {
      type = types.str;
      default = "homepage.local";
      description = "Domain name for the homepage dashboard";
    };

    title = mkOption {
      type = types.str;
      default = "Fleet Dashboard";
      description = "Title displayed on the homepage";
    };

    # Service registry for automatic service discovery
    serviceRegistry = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name for the service";
          };

          description = mkOption {
            type = types.str;
            default = "";
            description = "Description of the service";
          };

          icon = mkOption {
            type = types.str;
            default = "mdi-application";
            description = "Icon for the service (mdi-* or si-* or URL)";
          };

          href = mkOption {
            type = types.str;
            description = "URL to the service";
          };

          siteMonitor = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "URL to monitor for uptime (defaults to href)";
          };

          category = mkOption {
            type = types.enum ["Apps" "Dev" "Monitoring" "Infrastructure" "Media" "Services"];
            default = "Services";
            description = "Category for grouping services on the dashboard";
          };

          widget = mkOption {
            type = types.nullOr (types.submodule {
              options = {
                type = mkOption {
                  type = types.str;
                  description = "Widget type (e.g., prometheus, grafana, etc.)";
                };

                url = mkOption {
                  type = types.str;
                  description = "URL for the widget API";
                };

                fields = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Fields to display in the widget";
                };
              };
            });
            default = null;
            description = "Optional widget configuration for the service";
          };
        };
      });
      default = {};
      description = "Registry of services to display on the homepage";
      internal = true;
    };

    # Manual bookmarks
    # Structure: [ { CategoryName = [ { BookmarkName = { abbr, href, ... } } ] } ]
    bookmarks = mkOption {
      type = types.listOf (types.attrsOf (types.listOf (types.attrsOf (types.attrsOf types.str))));
      default = [];
      description = "Manual bookmarks configuration for homepage-dashboard";
      example = [
        {
          Developer = [
            {
              Github = {
                abbr = "GH";
                href = "https://github.com/";
              };
            }
          ];
        }
      ];
    };

    # Extra widgets
    widgets = mkOption {
      type = types.listOf types.attrs;
      default = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/";
          };
        }
        {
          search = {
            provider = "duckduckgo";
            target = "_blank";
          };
        }
      ];
      description = "Homepage widgets configuration";
    };

    # Enable Glances integration
    enableGlances = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Glances system monitoring integration";
    };

    glancesPort = mkOption {
      type = types.port;
      default = 61208;
      description = "Port for Glances web server";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # GLANCES SERVICE (System Monitoring)
    # --------------------------------------------------------------------------

    services.glances = mkIf cfg.enableGlances {
      enable = true;
      port = cfg.glancesPort;
    };

    # --------------------------------------------------------------------------
    # HOMEPAGE DASHBOARD SERVICE
    # --------------------------------------------------------------------------

    services.homepage-dashboard = let
      # Group services by category
      servicesByCategory = category:
        filterAttrs
        (_name: svc: svc.category == category)
        cfg.serviceRegistry;

      # Convert service registry entry to homepage format
      mkServiceEntry = _name: svc: {
        "${svc.name}" =
          {
            icon = svc.icon;
            description = svc.description;
            href = svc.href;
            siteMonitor = svc.siteMonitor or svc.href;
          }
          // (optionalAttrs (svc.widget != null) {
            widget = svc.widget;
          });
      };

      # Build category section
      mkCategorySection = category: let
        services = servicesByCategory category;
      in
        optional (services != {}) {
          "${category}" =
            mapAttrsToList mkServiceEntry services;
        };

      # All categories
      categories = ["Dev" "Monitoring" "Apps" "Infrastructure" "Media" "Services"];

      # Build services list
      allServices =
        concatLists (map mkCategorySection categories);

      # Glances widgets
      glancesWidgets = optional cfg.enableGlances {
        Glances = [
          {
            Info = {
              widget = {
                type = "glances";
                url = "http://localhost:${toString cfg.glancesPort}";
                metric = "info";
                chart = false;
                version = 4;
              };
            };
          }
          {
            CPU = {
              widget = {
                type = "glances";
                url = "http://localhost:${toString cfg.glancesPort}";
                metric = "cpu";
                chart = true;
                version = 4;
              };
            };
          }
          {
            Memory = {
              widget = {
                type = "glances";
                url = "http://localhost:${toString cfg.glancesPort}";
                metric = "memory";
                chart = true;
                version = 4;
              };
            };
          }
          {
            Network = {
              widget = {
                type = "glances";
                url = "http://localhost:${toString cfg.glancesPort}";
                metric = "network:eth0";
                chart = false;
                version = 4;
              };
            };
          }
        ];
      };
    in {
      enable = true;
      listenPort = cfg.port;
      allowedHosts = cfg.domain;

      settings = {
        title = cfg.title;
        headerStyle = "clean";
        statusStyle = "dot";
        hideVersion = true;
        layout =
          [
            {
              Glances = {
                header = false;
                style = "row";
                columns = 4;
              };
            }
          ]
          ++ map (cat: {
            "${cat}" = {
              header = true;
              style = "column";
            };
          })
          categories;
      };

      widgets = cfg.widgets;

      services = glancesWidgets ++ allServices;

      bookmarks = cfg.bookmarks;
    };

    # --------------------------------------------------------------------------
    # REVERSE PROXY REGISTRATION
    # --------------------------------------------------------------------------

    fleet.networking.reverseProxy.serviceRegistry.homepage = {
      port = cfg.port;
      labels = {
        "fleet.reverse-proxy.enable" = "true";
        "fleet.reverse-proxy.domain" = cfg.domain;
        "fleet.reverse-proxy.ssl" = "true";
      };
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [cfg.port] ++ optional cfg.enableGlances cfg.glancesPort;
  };
}
