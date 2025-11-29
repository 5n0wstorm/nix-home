{
  config,
  lib,
  ...
}:
with lib;
{
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
              "fleet.reverse-proxy.ssl-type" = "acme";  # "acme" or "selfsigned"
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
      domain = labels."fleet.reverse-proxy.domain" or "${serviceName}.local";
      target = labels."fleet.reverse-proxy.target" or "127.0.0.1";
      port = labels."fleet.reverse-proxy.port" or serviceConfig.port or 80;
      extraConfig = labels."fleet.reverse-proxy.extra-config" or "";
      enableSSL = labels."fleet.reverse-proxy.ssl" != "false";
      sslType = labels."fleet.reverse-proxy.ssl-type" or "acme";  # "acme" or "selfsigned"
      useACME = cfg.enableACME && enableSSL && sslType == "acme";
      useSelfSigned = cfg.enableTLS && enableSSL && sslType == "selfsigned";
    in {
      enableACME = useACME;
      forceSSL = (cfg.enableTLS && enableSSL) || useACME;

      sslCertificate = mkIf useSelfSigned "/var/lib/fleet-ca/certs/${domain}/cert.pem";
      sslCertificateKey = mkIf useSelfSigned "/var/lib/fleet-ca/certs/${domain}/key.pem";

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

  in mkIf cfg.enable {

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
      virtualHosts = mapAttrs mkVirtualHost cfg.routes //
        (mapAttrs mkServiceVirtualHost
          (filterAttrs (serviceName: serviceConfig:
            (serviceConfig.labels."fleet.reverse-proxy.enable" or "false") == "true"
          ) cfg.serviceRegistry));
    };

    # --------------------------------------------------------------------------
    # ACME / LET'S ENCRYPT CONFIGURATION
    # --------------------------------------------------------------------------

    security.acme = mkIf cfg.enableACME {
      acceptTerms = true;
      defaults = {
        email = cfg.acmeEmail;
        dnsProvider = "cloudflare";
        credentialsFile = if cfg.cloudflareCredentialsFile != null
          then cfg.cloudflareCredentialsFile
          else "/etc/cloudflare-credentials.ini";
        group = "nginx";
        # Prefer existing certificates to avoid unnecessary DNS challenges
        renewInterval = "monthly";
      };

      # Pre-populate certificates from SOPS if they exist
      certs = let
        serviceDomains = mapAttrsToList (serviceName: serviceConfig: serviceConfig.labels."fleet.reverse-proxy.domain" or "${serviceName}.local") (filterAttrs (serviceName: serviceConfig: (serviceConfig.labels."fleet.reverse-proxy.enable" or "false") == "true" && (serviceConfig.labels."fleet.reverse-proxy.ssl-type" or "acme") == "acme") cfg.serviceRegistry);
      in mkMerge (map (domain: {
        "${domain}" = {
          # If certificate exists in SOPS, use it; otherwise generate new one
          webroot = null;
          dnsProvider = "cloudflare";
          credentialsFile = if cfg.cloudflareCredentialsFile != null
            then cfg.cloudflareCredentialsFile
            else "/etc/cloudflare-credentials.ini";
          group = "nginx";
          email = cfg.acmeEmail;
        };
      }) serviceDomains);
    };

    # --------------------------------------------------------------------------
    # CLOUDFLARE CREDENTIALS FOR ACME DNS CHALLENGE
    # --------------------------------------------------------------------------

    environment.etc."cloudflare-credentials.ini" = mkIf (cfg.enableACME && cfg.cloudflareCredentialsFile == null) {
      text = ''
        # Cloudflare API credentials for ACME DNS challenge
        dns_cloudflare_api_token = ${config.sops.secrets."cloudflare_api_token".path or "/run/secrets/cloudflare_api_token"}
      '';
      mode = "0400";
      user = "acme";
      group = "acme";
    };

    # --------------------------------------------------------------------------
    # ACME CERTIFICATE MANAGEMENT
    # --------------------------------------------------------------------------

    systemd.services.acme-cert-backup = mkIf cfg.enableACME {
      description = "Backup ACME certificates to SOPS-managed location";
      wantedBy = ["multi-user.target"];
      after = ["acme-finished.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = let
        certBackupDir = "/var/lib/fleet-acme-certs";
        serviceDomains = mapAttrsToList (serviceName: serviceConfig: serviceConfig.labels."fleet.reverse-proxy.domain" or "${serviceName}.local") (filterAttrs (serviceName: serviceConfig: (serviceConfig.labels."fleet.reverse-proxy.enable" or "false") == "true" && (serviceConfig.labels."fleet.reverse-proxy.ssl-type" or "acme") == "acme") cfg.serviceRegistry);
      in ''
        set -euo pipefail

        # Create backup directory if it doesn't exist
        mkdir -p "${certBackupDir}"

        # Function to backup certificates for a domain
        backup_cert() {
          local domain="$1"
          local acme_dir="/var/lib/acme/$domain"
          local backup_dir="${certBackupDir}/$domain"

          if [[ -d "$acme_dir" && -f "$acme_dir/fullchain.pem" && -f "$acme_dir/key.pem" ]]; then
            echo "Backing up certificates for $domain..."
            mkdir -p "$backup_dir"
            cp "$acme_dir/fullchain.pem" "$backup_dir/"
            cp "$acme_dir/key.pem" "$backup_dir/"
            chmod 600 "$backup_dir"/*.pem
          fi
        }

        # Backup certificates for all service domains that use ACME
        ${concatMapStringsSep "\n" (domain: "backup_cert \"${domain}\"") serviceDomains}
      '';
    };

    # --------------------------------------------------------------------------
    # CERTIFICATE ENCRYPTION HELPER SCRIPT
    # --------------------------------------------------------------------------

    # Create a helper script for encrypting certificates with SOPS
    environment.etc."fleet-cert-encrypt.sh" = mkIf cfg.enableACME {
      text = ''
        #!/bin/bash
        # Helper script to encrypt ACME certificates with SOPS for reproducible builds
        # Usage: fleet-cert-encrypt.sh [domain]

        set -euo pipefail

        CERT_BACKUP_DIR="/var/lib/fleet-acme-certs"
        SOPS_CONFIG="${config.sops.defaultSopsFile or "/etc/nixos/secrets/secrets.yaml"}"

        if [[ $# -eq 0 ]]; then
          echo "Usage: $0 <domain> [domain2] ..."
          echo "Available domains with certificates:"
          find "$CERT_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
          exit 1
        fi

        for domain in "$@"; do
          cert_dir="$CERT_BACKUP_DIR/$domain"
          if [[ ! -d "$cert_dir" ]]; then
            echo "Error: Certificate directory not found: $cert_dir"
            echo "Run 'fleet-cert-backup' service first or wait for ACME to generate certificates"
            continue
          fi

          echo "Encrypting certificates for $domain..."

          # Encrypt fullchain.pem
          if [[ -f "$cert_dir/fullchain.pem" ]]; then
            fullchain_key="${domain}_acme_fullchain"
            echo "Encrypting fullchain.pem as $fullchain_key"
            sops --encrypt --input-type binary "$cert_dir/fullchain.pem" > "$cert_dir/fullchain.pem.enc"
            mv "$cert_dir/fullchain.pem.enc" "$SOPS_CONFIG.tmp"
            # Note: You need to manually merge this into your main SOPS file
            echo "Certificate encrypted. Run: sops edit $SOPS_CONFIG"
            echo "Add the encrypted content as: ${fullchain_key}: |"
            cat "$SOPS_CONFIG.tmp"
            rm "$SOPS_CONFIG.tmp"
          fi

          # Encrypt key.pem
          if [[ -f "$cert_dir/key.pem" ]]; then
            key_key="${domain}_acme_key"
            echo "Encrypting key.pem as $key_key"
            sops --encrypt --input-type binary "$cert_dir/key.pem" > "$cert_dir/key.pem.enc"
            mv "$cert_dir/key.pem.enc" "$SOPS_CONFIG.tmp"
            echo "Private key encrypted. Run: sops edit $SOPS_CONFIG"
            echo "Add the encrypted content as: ${key_key}: |"
            cat "$SOPS_CONFIG.tmp"
            rm "$SOPS_CONFIG.tmp"
          fi
        done

        echo "Certificates encrypted. Remember to commit the updated SOPS file!"
      '';
      mode = "0755";
    };

    # --------------------------------------------------------------------------
    # CERTIFICATE RESTORATION FROM SOPS FOR REPRODUCIBLE BUILDS
    # --------------------------------------------------------------------------

    # Restore ACME certificates from SOPS secrets if they exist
    systemd.services.acme-cert-restore = mkIf cfg.enableACME {
      description = "Restore ACME certificates from SOPS secrets";
      wantedBy = ["multi-user.target"];
      before = ["nginx.service"];
      after = ["sops-nix.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = let
        acmeDir = "/var/lib/acme";
        serviceDomains = mapAttrsToList (serviceName: serviceConfig: serviceConfig.labels."fleet.reverse-proxy.domain" or "${serviceName}.local") (filterAttrs (serviceName: serviceConfig: (serviceConfig.labels."fleet.reverse-proxy.enable" or "false") == "true" && (serviceConfig.labels."fleet.reverse-proxy.ssl-type" or "acme") == "acme") cfg.serviceRegistry);
      in ''
        set -euo pipefail

        # Function to restore certificates for a domain
        restore_cert() {
          local domain="$1"
          local domain_dir="${acmeDir}/$domain"

          # Check if encrypted certificates exist in SOPS
          local fullchain_key="${domain}_acme_fullchain"
          local key_key="${domain}_acme_key"

          local has_fullchain=false
          local has_key=false

          # Check if the secrets exist (this is a bit hacky but works)
          if [[ -f "/run/secrets/${fullchain_key}" ]]; then
            has_fullchain=true
          fi
          if [[ -f "/run/secrets/${key_key}" ]]; then
            has_key=true
          fi

          if [[ "$has_fullchain" == "true" && "$has_key" == "true" ]]; then
            echo "Restoring certificates for $domain from SOPS..."
            mkdir -p "$domain_dir"
            cp "/run/secrets/${fullchain_key}" "$domain_dir/fullchain.pem"
            cp "/run/secrets/${key_key}" "$domain_dir/key.pem"
            chmod 600 "$domain_dir/key.pem"
            chmod 644 "$domain_dir/fullchain.pem"
            chown -R acme:acme "$domain_dir"
            echo "Certificates restored for $domain"
          else
            echo "No encrypted certificates found for $domain, will generate new ones"
          fi
        }

        # Restore certificates for all service domains that use ACME
        ${concatMapStringsSep "\n" (domain: "restore_cert \"${domain}\"") serviceDomains}
      '';
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
