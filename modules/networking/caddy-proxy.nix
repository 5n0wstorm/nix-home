{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.fleet.networking.reverseProxy;
  acmeCfg = config.fleet.security.acme;
  authCfg = config.fleet.security.authelia;
in {
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.networking.reverseProxy = {
    enable = mkEnableOption "Caddy reverse proxy";

    httpPort = mkOption {
      type = types.port;
      default = 80;
      description = "HTTP port for Caddy";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 443;
      description = "HTTPS port for Caddy";
    };

    enableTLS = mkOption {
      type = types.bool;
      default = false;
      description = "Enable TLS/SSL using the fleet ACME wildcard certificate";
    };

    enableAuthelia = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable Authelia authentication for all proxied services.
        Services can opt-out using the "fleet.authelia.bypass" label.
      '';
    };

    # Service registry for pluggable services
    serviceRegistry = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          port = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "Default port for the service";
          };

          labels = mkOption {
            type = types.attrsOf types.str;
            default = {};
            description = "Labels for configuring reverse proxy behavior";
            example = {
              "fleet.reverse-proxy.enable" = "true";
              "fleet.reverse-proxy.domain" = "myapp.example.com";
              "fleet.reverse-proxy.ssl" = "true";
              "fleet.reverse-proxy.websockets" = "false";
              "fleet.authelia.bypass" = "true";
            };
          };
        };
      });
      default = {};
      description = "Registry of services that can be automatically proxied";
      internal = true;
    };

    routes = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          target = mkOption {
            type = types.str;
            description = "Target host IP or hostname";
          };

          port = mkOption {
            type = types.port;
            description = "Target port";
          };

          description = mkOption {
            type = types.str;
            default = "";
            description = "Description of this route";
          };

          ssl = mkOption {
            type = types.bool;
            default = true;
            description = "Enable SSL for this route";
          };

          bypassAuth = mkOption {
            type = types.bool;
            default = false;
            description = "Bypass Authelia authentication for this route";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Additional Caddy configuration for this route";
          };
        };
      });
      default = {};
      description = "Hostname to backend mapping";
      example = {
        "jenkins.example.com" = {
          target = "192.168.122.55";
          port = 8888;
          description = "Jenkins CI/CD";
        };
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = let
    # Check if ACME is properly configured for TLS
    useAcmeTLS = cfg.enableTLS && acmeCfg.enable;

    # Check if Authelia protection is active
    useAuthelia = cfg.enableAuthelia && authCfg.enable;

    # Authelia forward_auth snippet for Caddy
    # Based on: https://www.authelia.com/integration/proxies/caddy/
    autheliaSnippet = ''
      forward_auth localhost:${toString authCfg.port} {
        uri /api/authz/forward-auth
        copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
      }
    '';

    # Helper function to extract domain from service config
    getServiceDomain = serviceName: serviceConfig: let
      labels = serviceConfig.labels or {};
    in
      labels."fleet.reverse-proxy.domain" or "${serviceName}.${acmeCfg.domain}";

    # Generate Caddy virtual host config for a route
    mkRouteConfig = domain: routeConfig: let
      upstream = "http://${routeConfig.target}:${toString routeConfig.port}";
      needsAuth = useAuthelia && !routeConfig.bypassAuth;
    in ''
      ${domain} {
        ${optionalString useAcmeTLS ''
        tls ${acmeCfg.certPath} ${acmeCfg.keyPath}
      ''}
        ${optionalString needsAuth autheliaSnippet}
        reverse_proxy ${upstream}
        ${routeConfig.extraConfig}
      }
    '';

    # Generate Caddy virtual host config for a service registry entry
    mkServiceConfig = serviceName: serviceConfig: let
      labels = serviceConfig.labels or {};
      domain = getServiceDomain serviceName serviceConfig;
      target = labels."fleet.reverse-proxy.target" or "127.0.0.1";
      port = labels."fleet.reverse-proxy.port" or serviceConfig.port or 80;
      upstream = "http://${target}:${toString port}";
      bypassAuth = (labels."fleet.authelia.bypass" or "false") == "true";
      needsAuth = useAuthelia && !bypassAuth;
      extraConfig = labels."fleet.reverse-proxy.extra-config" or "";
    in ''
      ${domain} {
        ${optionalString useAcmeTLS ''
        tls ${acmeCfg.certPath} ${acmeCfg.keyPath}
      ''}
        ${optionalString needsAuth autheliaSnippet}
        reverse_proxy ${upstream}
        ${extraConfig}
      }
    '';

    # Filter enabled services
    enabledServices =
      filterAttrs (
        _serviceName: serviceConfig:
          (serviceConfig.labels."fleet.reverse-proxy.enable" or "false") == "true"
      )
      cfg.serviceRegistry;

    # Generate all route configs
    routeConfigs = concatStringsSep "\n" (mapAttrsToList mkRouteConfig cfg.routes);

    # Generate all service configs
    serviceConfigs = concatStringsSep "\n" (mapAttrsToList mkServiceConfig enabledServices);

    # Full Caddyfile
    caddyConfig = ''
      # Global options
      {
        ${optionalString (!useAcmeTLS) "auto_https off"}
        http_port ${toString cfg.httpPort}
        https_port ${toString cfg.httpsPort}
      }

      ${optionalString useAuthelia ''
        # Authelia forward_auth snippet (can be imported)
        (authelia) {
          forward_auth localhost:${toString authCfg.port} {
            uri /api/authz/forward-auth
            copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
          }
        }
      ''}

      # Routes from manual configuration
      ${routeConfigs}

      # Routes from service registry
      ${serviceConfigs}
    '';
  in
    mkIf cfg.enable {
      # --------------------------------------------------------------------------
      # ASSERTIONS
      # --------------------------------------------------------------------------

      assertions = [
        {
          assertion = cfg.enableTLS -> acmeCfg.enable;
          message = ''
            fleet.networking.reverseProxy.enableTLS requires fleet.security.acme.enable.
            Please configure the ACME module with your wildcard certificate settings.
          '';
        }
        {
          assertion = cfg.enableAuthelia -> authCfg.enable;
          message = ''
            fleet.networking.reverseProxy.enableAuthelia requires fleet.security.authelia.enable.
            Please configure the Authelia module first.
          '';
        }
      ];

      # --------------------------------------------------------------------------
      # CADDY SERVICE
      # --------------------------------------------------------------------------

      services.caddy = {
        enable = true;
        configFile = pkgs.writeText "Caddyfile" caddyConfig;
      };

      # Ensure Caddy can read ACME certificates
      users.users.caddy.extraGroups = mkIf useAcmeTLS ["acme"];

      # --------------------------------------------------------------------------
      # SYSTEMD DEPENDENCIES
      # --------------------------------------------------------------------------

      systemd.services.caddy = mkIf useAcmeTLS {
        wants = ["acme-finished-${acmeCfg.domain}.target"];
        after = ["acme-finished-${acmeCfg.domain}.target"];
      };

      # --------------------------------------------------------------------------
      # FIREWALL CONFIGURATION
      # --------------------------------------------------------------------------

      networking.firewall.allowedTCPPorts = [
        cfg.httpPort
        cfg.httpsPort
      ];
    };
}
