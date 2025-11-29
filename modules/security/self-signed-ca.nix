{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================
  #
  # This module provides self-signed certificate generation using minica,
  # which supports both regular domains and wildcard certificates.
  #
  # Wildcard certificates are useful for development environments where
  # you need certificates for multiple subdomains of the same domain.
  #
  # Example usage:
  #   fleet.security.selfSignedCA = {
  #     enable = true;
  #     wildcardDomains = ["*.local"];
  #     domains = ["specific.example.com"];
  #   };
  #

  options.fleet.security.selfSignedCA = {
    enable = mkEnableOption "Self-signed Certificate Authority";

    caName = mkOption {
      type = types.str;
      default = "Fleet Internal CA";
      description = "Name of the Certificate Authority";
    };

    domains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of domains to generate certificates for";
      example = ["jenkins.local" "grafana.local"];
    };

    wildcardDomains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of wildcard domains to generate certificates for";
      example = ["*.local" "*.example.com"];
    };

    validityDays = mkOption {
      type = types.int;
      default = 365;
      description = "Certificate validity in days";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = let
    cfg = config.fleet.security.selfSignedCA;

    # Get domains from service registry that use self-signed certificates
    serviceRegistry = config.fleet.networking.reverseProxy.serviceRegistry or {};
    serviceDomains = mapAttrsToList (serviceName: serviceConfig:
      serviceConfig.labels."fleet.reverse-proxy.domain" or "${serviceName}.local"
    ) (filterAttrs (serviceName: serviceConfig:
      (serviceConfig.labels."fleet.reverse-proxy.enable" or "false") == "true" &&
      (serviceConfig.labels."fleet.reverse-proxy.ssl" or "true") != "false" &&
      (serviceConfig.labels."fleet.reverse-proxy.ssl-type" or "acme") == "selfsigned"
    ) serviceRegistry);

    allDomains = cfg.domains ++ serviceDomains;
    allWildcardDomains = cfg.wildcardDomains;
  in mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # CA AND CERTIFICATE GENERATION
    # --------------------------------------------------------------------------

    systemd.services.fleet-ca-setup = {
      description = "Setup Fleet Internal Certificate Authority";
      wantedBy = ["multi-user.target"];
      before = ["nginx.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };

      script = ''
        set -euo pipefail

        CA_DIR="/var/lib/fleet-ca"

        # Create CA directory
        mkdir -p "$CA_DIR"

        # Change to CA directory for minica operations
        cd "$CA_DIR"

        # Generate CA and certificates using minica if not already done
        if [[ ! -f "minica.pem" ]]; then
          echo "Generating CA and certificates with minica..."

          # Build minica command arguments
          MINICA_ARGS=()

          # Add wildcard domains
          ${concatMapStringsSep "\n" (domain: ''
            [[ -n "${domain}" ]] && MINICA_ARGS+=("${domain}")
          '') allWildcardDomains}

          # Add regular domains
          ${concatMapStringsSep "\n" (domain: ''
            [[ -n "${domain}" ]] && MINICA_ARGS+=("${domain}")
          '') allDomains}

          # Generate certificates if we have domains
          if [[ ''${#MINICA_ARGS[@]} -gt 0 ]]; then
            echo "Generating certificates for: ''${MINICA_ARGS[*]}"
            ${pkgs.minica}/bin/minica \
              --ca-cert=minica.pem \
              --ca-key=minica-key.pem \
              --domains="''${MINICA_ARGS[*]}" \
              --validity-days=${toString cfg.validityDays}

            # Set proper permissions
            chmod 600 minica-key.pem
            chmod 644 minica.pem
            find . -name "*.pem" -type f -exec chmod 644 {} \;
            find . -name "*-key.pem" -type f -exec chmod 600 {} \;
          else
            echo "No domains specified, generating minimal CA only..."
            ${pkgs.minica}/bin/minica \
              --ca-cert=minica.pem \
              --ca-key=minica-key.pem \
              --domains="${cfg.caName}.local"
          fi
        fi

        # Create symlinks for backward compatibility and easy access
        ln -sf minica.pem ca-cert.pem
        ln -sf minica-key.pem ca-key.pem

        # Set ownership for nginx
        chown -R nginx:nginx "$CA_DIR"

        echo "Fleet CA setup complete!"
        echo "CA certificate available at: $CA_DIR/ca-cert.pem"
        echo "To trust this CA, add the CA certificate to your browser/system trust store."
      '';
    };

    # --------------------------------------------------------------------------
    # CERTIFICATE STORE
    # --------------------------------------------------------------------------

    # Create a placeholder CA certificate for build time
    environment.etc."fleet-ca-placeholder.pem".text = ''
      -----BEGIN CERTIFICATE-----
      MIIBkTCB+wIJANK4bX0QRtlbMA0GCSqGSIb3DQEBCwUAMBQxEjAQBgNVBAMMCVRl
      c3QgUGxhY2UwHhcNMjMwMTAxMDAwMDAwWhcNMjQwMTAxMDAwMDAwWjAUMRIwEAYD
      VQQDDAlUZXN0IFBsYWNlMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBANK4bX0QRtlb
      -----END CERTIFICATE-----
    '';

    # Use a systemd path unit to dynamically add the real CA when it's created
    systemd.paths.fleet-ca-trust = {
      wantedBy = ["multi-user.target"];
      pathConfig = {
        PathExists = "/var/lib/fleet-ca/ca-cert.pem";
      };
    };

    systemd.services.fleet-ca-trust = {
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Copy the real CA certificate to the system trust store
        mkdir -p /etc/ssl/certs/fleet
        cp /var/lib/fleet-ca/ca-cert.pem /etc/ssl/certs/fleet/ca-cert.pem

        # Update the CA bundle
        ${pkgs.cacert}/bin/update-ca-certificates || true
      '';
    };

    # --------------------------------------------------------------------------
    # USERS AND GROUPS
    # --------------------------------------------------------------------------

    users.users.nginx = {
      isSystemUser = true;
      group = "nginx";
    };

    users.groups.nginx = {};
  };
}
