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

      customCSS = ''
        /* Fleet Dashboard - Catppuccin Latte Theme */
        @import url('https://fonts.googleapis.com/css2?family=Lexend:wght@300;400;500;600;700&display=swap');

        :root {
          /* Catppuccin Latte Palette */
          --ctp-rosewater: #dc8a78;
          --ctp-flamingo: #dd7878;
          --ctp-pink: #ea76cb;
          --ctp-mauve: #8839ef;
          --ctp-red: #d20f39;
          --ctp-maroon: #e64553;
          --ctp-peach: #fe640b;
          --ctp-yellow: #df8e1d;
          --ctp-green: #40a02b;
          --ctp-teal: #179299;
          --ctp-sky: #04a5e5;
          --ctp-sapphire: #209fb5;
          --ctp-blue: #1e66f5;
          --ctp-lavender: #7287fd;
          --ctp-text: #4c4f69;
          --ctp-subtext1: #5c5f77;
          --ctp-subtext0: #6c6f85;
          --ctp-overlay2: #7c7f93;
          --ctp-overlay1: #8c8fa1;
          --ctp-overlay0: #9ca0b0;
          --ctp-surface2: #acb0be;
          --ctp-surface1: #bcc0cc;
          --ctp-surface0: #ccd0da;
          --ctp-base: #eff1f5;
          --ctp-mantle: #e6e9ef;
          --ctp-crust: #dce0e8;
        }

        body, html {
          font-family: 'Lexend', sans-serif !important;
          background: linear-gradient(135deg, var(--ctp-base) 0%, var(--ctp-mantle) 100%) !important;
          color: var(--ctp-text) !important;
        }

        /* Override dark theme defaults */
        .dark body, .dark html,
        [data-theme="dark"] body,
        [data-theme="dark"] html {
          background: linear-gradient(135deg, var(--ctp-base) 0%, var(--ctp-mantle) 100%) !important;
          color: var(--ctp-text) !important;
        }

        /* Main container */
        #page_container,
        main {
          background: transparent !important;
        }

        /* Typography */
        .font-medium {
          font-weight: 600 !important;
          color: var(--ctp-text) !important;
        }

        .font-light {
          font-weight: 400 !important;
          color: var(--ctp-subtext1) !important;
        }

        .font-thin {
          font-weight: 300 !important;
          color: var(--ctp-subtext0) !important;
        }

        /* Information widgets */
        #information-widgets {
          padding: 1.5rem;
        }

        /* Hide footer */
        div#footer {
          display: none;
        }

        /* Service groups */
        .services-group {
          padding-bottom: 2rem;
        }

        .services-group h2,
        .service-group-name {
          color: var(--ctp-mauve) !important;
          font-weight: 600 !important;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          font-size: 0.875rem !important;
        }

        /* Service cards */
        .service {
          background: var(--ctp-surface0) !important;
          border: 1px solid var(--ctp-surface1) !important;
          border-radius: 12px !important;
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
          box-shadow: 0 2px 8px rgba(76, 79, 105, 0.08);
        }

        .service:hover {
          transform: translateY(-3px);
          box-shadow: 0 12px 32px rgba(136, 57, 239, 0.12);
          border-color: var(--ctp-lavender) !important;
        }

        .service a {
          color: var(--ctp-text) !important;
        }

        .service .text-xs {
          color: var(--ctp-subtext0) !important;
        }

        /* Widgets */
        .widget {
          background: var(--ctp-surface0) !important;
          border-radius: 12px !important;
          border: 1px solid var(--ctp-surface1) !important;
        }

        /* Status indicators */
        .status-dot-online,
        .online {
          background-color: var(--ctp-green) !important;
        }

        .status-dot-offline,
        .offline {
          background-color: var(--ctp-red) !important;
        }

        /* Search widget */
        input[type="text"],
        input[type="search"] {
          background: var(--ctp-surface0) !important;
          border: 1px solid var(--ctp-surface1) !important;
          border-radius: 8px !important;
          color: var(--ctp-text) !important;
        }

        input::placeholder {
          color: var(--ctp-overlay0) !important;
        }

        /* Bookmarks */
        .bookmark {
          background: var(--ctp-surface0) !important;
          border: 1px solid var(--ctp-surface1) !important;
          border-radius: 8px !important;
          color: var(--ctp-text) !important;
        }

        .bookmark:hover {
          border-color: var(--ctp-sapphire) !important;
          background: var(--ctp-mantle) !important;
        }

        /* Resource widgets */
        .resource-usage {
          color: var(--ctp-text) !important;
        }

        /* Progress bars */
        .progress-bar,
        [role="progressbar"] {
          background: var(--ctp-surface1) !important;
          border-radius: 4px !important;
        }

        .progress-bar-inner,
        [role="progressbar"] > div {
          background: linear-gradient(90deg, var(--ctp-sapphire), var(--ctp-blue)) !important;
          border-radius: 4px !important;
        }

        /* Glances widgets */
        .glances-widget {
          background: var(--ctp-surface0) !important;
        }

        /* Links */
        a {
          color: var(--ctp-blue) !important;
        }

        a:hover {
          color: var(--ctp-sapphire) !important;
        }

        /* Scrollbar */
        ::-webkit-scrollbar {
          width: 8px;
          height: 8px;
        }

        ::-webkit-scrollbar-track {
          background: var(--ctp-mantle);
        }

        ::-webkit-scrollbar-thumb {
          background: var(--ctp-surface2);
          border-radius: 4px;
        }

        ::-webkit-scrollbar-thumb:hover {
          background: var(--ctp-overlay0);
        }
      '';

      customJS = ''
        // Fleet Dashboard Custom JS
        console.log('Fleet Dashboard loaded');
      '';
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
