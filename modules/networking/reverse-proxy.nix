{
  config,
  lib,
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
    enable = mkEnableOption "Nginx reverse proxy";

    httpPort = mkOption {
      type = types.port;
      default = 80;
      description = "HTTP port for nginx";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 443;
      description = "HTTPS port for nginx";
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
              "fleet.reverse-proxy.extra-config" = "client_max_body_size 100M;";
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
            description = "Additional nginx configuration for this route";
            example = ''
              client_max_body_size 100M;
              proxy_read_timeout 300;
            '';
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

    # Authelia nginx snippets for forward auth
    autheliaAuthSnippet = ''
      # Authelia forward authentication using ForwardAuth endpoint
      # This endpoint returns 302 with proper redirect handling
      auth_request /authelia-forward;
      auth_request_set $user $upstream_http_remote_user;
      auth_request_set $groups $upstream_http_remote_groups;
      auth_request_set $name $upstream_http_remote_name;
      auth_request_set $email $upstream_http_remote_email;
      auth_request_set $authelia_redirect $upstream_http_location;

      # Pass authentication info to backend
      proxy_set_header Remote-User $user;
      proxy_set_header Remote-Groups $groups;
      proxy_set_header Remote-Name $name;
      proxy_set_header Remote-Email $email;

      # Error handling - if Authelia returns 401, use the redirect URL from Authelia
      error_page 401 =302 $authelia_redirect;

      # Ensure the session cookie is forwarded properly
      proxy_set_header Cookie $http_cookie;
    '';

    # Authelia location blocks for each virtual host
    # Uses ForwardAuth endpoint which returns proper redirect Location header
    autheliaLocations = {
      "/authelia-forward" = {
        proxyPass = "http://127.0.0.1:${toString authCfg.port}/api/authz/forward-auth";
        extraConfig = ''
          internal;
          proxy_pass_request_body off;
          proxy_set_header Content-Length "";
          proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          proxy_set_header X-Original-Method $request_method;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-Uri $request_uri;
          proxy_set_header Cookie $http_cookie;
        '';
      };
    };

    # Helper function to create a virtual host configuration
    mkVirtualHost = _name: hostConfig: {
      # Use wildcard certificate from ACME module
      sslCertificate = mkIf (useAcmeTLS && hostConfig.ssl) acmeCfg.certPath;
      sslCertificateKey = mkIf (useAcmeTLS && hostConfig.ssl) acmeCfg.keyPath;
      forceSSL = useAcmeTLS && hostConfig.ssl;

      # Add Authelia location if enabled and not bypassed
      locations = mkMerge [
        (mkIf (useAuthelia && !hostConfig.bypassAuth) autheliaLocations)
        {
          "/" = {
            proxyPass = "http://${hostConfig.target}:${toString hostConfig.port}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              ${optionalString (useAuthelia && !hostConfig.bypassAuth) autheliaAuthSnippet}
              ${hostConfig.extraConfig}
            '';
          };
        }
      ];
    };

    # Helper function to extract domain from service config (used for keying)
    getServiceDomain = serviceName: serviceConfig: let
      labels = serviceConfig.labels or {};
    in
      labels."fleet.reverse-proxy.domain" or "${serviceName}.${acmeCfg.domain}";

    # Helper function to create virtual host config from service registry entry
    mkServiceVirtualHostConfig = serviceName: serviceConfig: let
      labels = serviceConfig.labels or {};
      target = labels."fleet.reverse-proxy.target" or "127.0.0.1";
      port = labels."fleet.reverse-proxy.port" or serviceConfig.port or 80;
      extraConfig = labels."fleet.reverse-proxy.extra-config" or "";
      enableSSL = (labels."fleet.reverse-proxy.ssl" or "true") != "false";
      bypassAuth = (labels."fleet.authelia.bypass" or "false") == "true";
    in {
      # Use wildcard certificate from ACME module
      sslCertificate = mkIf (useAcmeTLS && enableSSL) acmeCfg.certPath;
      sslCertificateKey = mkIf (useAcmeTLS && enableSSL) acmeCfg.keyPath;
      forceSSL = useAcmeTLS && enableSSL;

      # Add Authelia location if enabled and not bypassed
      locations = mkMerge [
        (mkIf (useAuthelia && !bypassAuth) autheliaLocations)
        {
          "/" = {
            proxyPass = "http://${target}:${toString port}";
            proxyWebsockets = (labels."fleet.reverse-proxy.websockets" or "false") == "true";
            extraConfig = ''
              ${optionalString (useAuthelia && !bypassAuth) autheliaAuthSnippet}
              ${extraConfig}
              ${labels."fleet.reverse-proxy.nginx-extra-config" or ""}
            '';
          };
        }
      ];
    };

    enabledServices =
      filterAttrs (
        _serviceName: serviceConfig:
          (serviceConfig.labels."fleet.reverse-proxy.enable" or "false") == "true"
      )
      cfg.serviceRegistry;
    serviceVirtualHosts = listToAttrs (
      mapAttrsToList (serviceName: serviceConfig: {
        name = getServiceDomain serviceName serviceConfig;
        value = mkServiceVirtualHostConfig serviceName serviceConfig;
      })
      enabledServices
    );
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
      # NGINX SERVICE
      # --------------------------------------------------------------------------

      services.nginx = {
        enable = true;

        # Default configuration
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        # Generate virtual hosts from manual routes and service registry
        # Routes are already keyed by domain, service registry is converted above
        virtualHosts = mapAttrs mkVirtualHost cfg.routes // serviceVirtualHosts;
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
