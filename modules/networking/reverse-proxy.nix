{
  config,
  lib,
  ...
}:
with lib; {
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
      description = "Enable TLS/SSL for all routes";
    };

    enableACME = mkOption {
      type = types.bool;
      default = false;
      description = "Enable ACME/Let's Encrypt certificates with DNS challenge";
    };

    acmeEmail = mkOption {
      type = types.str;
      default = "";
      description = "Email address for ACME certificate registration";
    };

    cloudflareCredentialsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to Cloudflare credentials file for DNS challenge";
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
              "fleet.reverse-proxy.domain" = "myapp.local";
              "fleet.reverse-proxy.ssl" = "true";
              "fleet.reverse-proxy.ssl-type" = "acme"; # Let's Encrypt ACME
              "fleet.reverse-proxy.websockets" = "false";
              "fleet.reverse-proxy.extra-config" = "client_max_body_size 100M;";
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
        "jenkins.fleet.local" = {
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
    cfg = config.fleet.networking.reverseProxy;

    # Helper function to create a virtual host configuration
    mkVirtualHost = name: hostConfig: {
      enableACME = cfg.enableACME;
      forceSSL = cfg.enableTLS;

      sslCertificate = mkIf (!cfg.enableACME && cfg.enableTLS) "/var/lib/fleet-ca/certs/${name}/cert.pem";
      sslCertificateKey = mkIf (!cfg.enableACME && cfg.enableTLS) "/var/lib/fleet-ca/certs/${name}/key.pem";

      locations."/" = {
        proxyPass = "http://${hostConfig.target}:${toString hostConfig.port}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          ${hostConfig.extraConfig}
        '';
      };
    };

    # Helper function to create virtual host from service registry entry
    mkServiceVirtualHost = serviceName: serviceConfig: let
      labels = serviceConfig.labels or {};
      domain = labels."fleet.reverse-proxy.domain" or "${serviceName}.sn0wstorm.com";
      target = labels."fleet.reverse-proxy.target" or "127.0.0.1";
      port = labels."fleet.reverse-proxy.port" or serviceConfig.port or 80;
      extraConfig = labels."fleet.reverse-proxy.extra-config" or "";
      enableSSL = labels."fleet.reverse-proxy.ssl" != "false";
    in {
      # Use wildcard Let's Encrypt certificate for all services
      sslCertificate = mkIf (cfg.enableTLS && enableSSL && cfg.enableACME) "/var/lib/acme/sn0wstorm.com/fullchain.pem";
      sslCertificateKey = mkIf (cfg.enableTLS && enableSSL && cfg.enableACME) "/var/lib/acme/sn0wstorm.com/key.pem";
      forceSSL = cfg.enableTLS && enableSSL && cfg.enableACME;

      locations."/" = {
        proxyPass = "http://${target}:${toString port}";
        proxyWebsockets = labels."fleet.reverse-proxy.websockets" == "true";
        extraConfig = ''
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          ${extraConfig}
          ${labels."fleet.reverse-proxy.nginx-extra-config" or ""}
        '';
      };
    };
  in
    mkIf cfg.enable {
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
        virtualHosts =
          mapAttrs mkVirtualHost cfg.routes
          // (mapAttrs mkServiceVirtualHost
            (filterAttrs (
                serviceName: serviceConfig:
                  (serviceConfig.labels."fleet.reverse-proxy.enable" or "false") == "true"
              )
              cfg.serviceRegistry));
      };



    # --------------------------------------------------------------------------




      # --------------------------------------------------------------------------
      # FIREWALL CONFIGURATION
      # --------------------------------------------------------------------------

      networking.firewall.allowedTCPPorts = [
        cfg.httpPort
        cfg.httpsPort
      ];
    };
}
